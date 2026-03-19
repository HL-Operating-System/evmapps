// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IPRJXV3Router {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);
}

contract HyperSwapPRJXV3Wrapper is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // TODO: Verify this address. Added a leading '0' to make it 40 hex chars.
    address public constant PRJX_ROUTER = 0x1EbDFC75FfE3ba3de61E7138a3E8706aC841Af9B;

    uint256 public constant MAX_FEE_BPS = 300;

    uint256 public feeBps;
    address public feeRecipient;

    mapping(uint24 => bool) public allowedPoolFees;

    event SwapExecuted(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 feeTaken
    );

    error InvalidAmount();
    error InvalidFee();
    error ZeroAddress();
    error InvalidPair();
    error FeeTierNotAllowed();
    error Expired();
    error SlippageExceeded();

    constructor(address _feeRecipient, uint256 _feeBps) Ownable(msg.sender) {
        if (_feeRecipient == address(0)) revert ZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert InvalidFee();

        feeRecipient = _feeRecipient;
        feeBps = _feeBps;

        allowedPoolFees[500] = true;
        allowedPoolFees[3000] = true;
        allowedPoolFees[10000] = true;
    }

    // --------------------------------------------------
    // Admin
    // --------------------------------------------------

    function setFee(uint256 _feeBps) external onlyOwner {
        if (_feeBps > MAX_FEE_BPS) revert InvalidFee();
        feeBps = _feeBps;
    }

    function setFeeRecipient(address _recipient) external onlyOwner {
        if (_recipient == address(0)) revert ZeroAddress();
        feeRecipient = _recipient;
    }

    function setAllowedPoolFee(uint24 feeTier, bool allowed) external onlyOwner {
        allowedPoolFees[feeTier] = allowed;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // --------------------------------------------------
    // Swap Methods
    // --------------------------------------------------

    /// @notice Standard swap for tokens that DO NOT support permit (e.g., WETH)
    function swapExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline
    ) external nonReentrant whenNotPaused returns (uint256 amountOut) {
        return _processSwap(tokenIn, tokenOut, poolFee, amountIn, amountOutMin, deadline);
    }

    /// @notice Swap for tokens that natively support EIP-2612 permits
    function swapExactInputSingleWithPermit(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused returns (uint256 amountOut) {
        if (deadline < block.timestamp) revert Expired();

        // 1️⃣ Execute permit
        IERC20Permit(tokenIn).permit(msg.sender, address(this), amountIn, permitDeadline, v, r, s);

        // 2️⃣ Continue with standard logic
        return _processSwap(tokenIn, tokenOut, poolFee, amountIn, amountOutMin, deadline);
    }

    // --------------------------------------------------
    // Internal Logic
    // --------------------------------------------------

    function _processSwap(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline
    ) internal returns (uint256 amountOut) {
        if (amountIn == 0) revert InvalidAmount();
        if (deadline < block.timestamp) revert Expired();
        if (tokenIn == tokenOut) revert InvalidPair();
        if (!allowedPoolFees[poolFee]) revert FeeTierNotAllowed();

        // Support for Fee-On-Transfer tokens: Measure exact received amount
        uint256 balanceBeforePull = IERC20(tokenIn).balanceOf(address(this));
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 actualAmountIn = IERC20(tokenIn).balanceOf(address(this)) - balanceBeforePull;

        // Take protocol fee
        uint256 feeAmount = (actualAmountIn * feeBps) / 10000;
        uint256 amountToSwap = actualAmountIn - feeAmount;

        if (feeAmount > 0) {
            IERC20(tokenIn).safeTransfer(feeRecipient, feeAmount);
        }

        // Modern safe approval (OZ v5)
        IERC20(tokenIn).forceApprove(PRJX_ROUTER, amountToSwap);

        uint256 balanceBeforeSwap = IERC20(tokenOut).balanceOf(address(this));

        // Execute swap
        IPRJXV3Router(PRJX_ROUTER).exactInputSingle(
            IPRJXV3Router.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: address(this),
                deadline: deadline,
                amountIn: amountToSwap,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            })
        );

        // Calculate and validate output
        amountOut = IERC20(tokenOut).balanceOf(address(this)) - balanceBeforeSwap;
        
        // Failsafe in case router output logic was altered
        if (amountOut < amountOutMin) revert SlippageExceeded();

        // Send output to user
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        emit SwapExecuted(msg.sender, tokenIn, tokenOut, actualAmountIn, amountOut, feeAmount);
    }
}