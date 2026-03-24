"use client";

import { useCallback } from "react";
import { useWriteContract, useAccount, useChainId, useSwitchChain, usePublicClient } from "wagmi";
import { parseUnits } from "viem";
import { HYPERSWAP_WRAPPER_ADDRESS } from "@/constants/constants";
import hyperswapWrapperAbi from "@/lib/hyperswap-wrapper-abi.json";
import { hyperEvm } from "viem/chains";
import type { Address } from "viem";

const ERC20_APPROVE_ABI = [
  { type: "function", name: "allowance", stateMutability: "view", inputs: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], outputs: [{ type: "bool" }] },
] as const;

/** Project X V3 pool fee tiers (basis points): 100=0.01%, 500=0.05%, 3000=0.3%, 10000=1% */
export const POOL_FEE_TIERS = [100, 500, 3000, 10000] as const;
export type PoolFeeTier = (typeof POOL_FEE_TIERS)[number];

/** Zero address = native HYPE (user sends value with tx) */
const NATIVE_HYPE = "0x0000000000000000000000000000000000000000" as Address;

/** Default pool fee for HYPE/USDC and similar pairs (0.3%) */
const DEFAULT_POOL_FEE: PoolFeeTier = 3000;

type SwapParams = {
  tokenIn: Address;
  tokenOut: Address;
  amountIn: string;
  amountInDecimals: number;
  amountOutMin: bigint;
  poolFee?: PoolFeeTier;
  deadline?: number;
};

/**
 * Hook to execute a swap via the HyperSwap PRJX V3 wrapper on HyperEVM.
 * Use address(0) for tokenIn when swapping native HYPE — value will be sent with the tx.
 */
export function usePrjxSwap() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync, isPending, error, reset } = useWriteContract();
  const publicClient = usePublicClient({ chainId: hyperEvm.id });

  const HYPER_EVM_CHAIN_ID = 999;

  const executeSwap = useCallback(
    async (params: SwapParams) => {
      if (!address) throw new Error("Connect wallet to swap");
      if (chainId !== HYPER_EVM_CHAIN_ID && switchChainAsync) {
        await switchChainAsync({ chainId: HYPER_EVM_CHAIN_ID });
        throw new Error("Switched to HyperEVM — try again.");
      }

      const {
        tokenIn,
        tokenOut,
        amountIn: amountInStr,
        amountInDecimals,
        amountOutMin,
        poolFee = DEFAULT_POOL_FEE,
        deadline = Math.floor(Date.now() / 1000) + 60 * 20, // 20 min
      } = params;

      const amountInWei = parseUnits(amountInStr, amountInDecimals);
      const isNativeIn = tokenIn === NATIVE_HYPE;

      // ERC20 tokenIn requires approval before swap — check and approve if needed
      if (!isNativeIn && publicClient) {
        const allowance = (await publicClient.readContract({
          address: tokenIn,
          abi: ERC20_APPROVE_ABI,
          functionName: "allowance",
          args: [address, HYPERSWAP_WRAPPER_ADDRESS],
        })) as bigint;
        if (allowance < amountInWei) {
          await writeContractAsync({
            address: tokenIn,
            abi: ERC20_APPROVE_ABI,
            functionName: "approve",
            args: [HYPERSWAP_WRAPPER_ADDRESS, amountInWei],
          });
        }
      }

      const tx = await writeContractAsync({
        address: HYPERSWAP_WRAPPER_ADDRESS,
        abi: hyperswapWrapperAbi as never,
        functionName: "swapExactInputSingle",
        args: [
          tokenIn,
          tokenOut,
          poolFee,
          amountInWei,
          amountOutMin,
          BigInt(deadline),
        ],
        value: isNativeIn ? amountInWei : 0n,
      });

      return tx;
    },
    [address, chainId, switchChainAsync, writeContractAsync, publicClient]
  );

  return {
    executeSwap,
    isPending,
    error,
    reset,
    isConnected,
    isWrongChain: chainId !== undefined && chainId !== HYPER_EVM_CHAIN_ID,
    switchToHyperEVM: () => switchChainAsync?.({ chainId: HYPER_EVM_CHAIN_ID }),
  };
}
