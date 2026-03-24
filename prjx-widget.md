"use client";

import { useState, useCallback } from "react";
import { ChevronDown, Eye, Wallet } from "lucide-react";
import { cn } from "@/lib/utils";
import Input from "@/components/shared/input";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { useAccount, useBalance, useReadContract } from "wagmi";
import { usePrjxSwap } from "@/hooks/use-prjx-swap";
import { usePrjxQuote } from "@/hooks/use-prjx-quote";
import { EVM_TOKENS, getTokenBySymbol, NATIVE_HYPE_ADDRESS } from "@/lib/evm-tokens";
import { formatUnits } from "viem";
import type { Address } from "viem";
import { toast } from "sonner";

const HYPER_EVM_CHAIN_ID = 999;

const ERC20_BALANCE_ABI = [
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
] as const;

const WIDGET_ACCENT = "#DAFFFF";

/** EVM token icons — uses image from token meta when available, else letter fallback */
function TokenIcon({ symbol }: { symbol: string }) {
  const token = getTokenBySymbol(symbol);
  const letter = symbol.charAt(0);
  const isGreen = symbol === "USDTO" || symbol === "USDC";

  // Icons display at 36×36px (h-9 w-9). Use 72×72 or 96×96 source images for crisp retina display.
  if (token?.icon) {
    return (
      <img
        src={token.icon}
        alt={symbol}
        className="h-9 w-9 shrink-0 rounded-full object-cover"
      />
    );
  }

  return (
    <div
      className={cn(
        "flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-sm font-semibold text-white",
        isGreen ? "bg-[#00c878]/80" : "bg-[#00964F]/80"
      )}
    >
      {letter}
    </div>
  );
}

const SWAPABLE_SYMBOLS = EVM_TOKENS.map((t) => t.symbol).filter(
  (s) => s !== "WHYPE" && s !== "USDTO"
);

function formatBalance(value: number): string {
  if (value >= 1e9) return value.toExponential(2);
  if (value >= 1e6) return value.toLocaleString("en-US", { maximumFractionDigits: 2 });
  if (value >= 1) return value.toLocaleString("en-US", { minimumFractionDigits: 0, maximumFractionDigits: 4 });
  if (value > 0) return value.toFixed(6);
  return "0";
}

/** EVM Token Swap widget — uses HyperSwap PRJX V3 wrapper on HyperEVM */
export default function EvmTokenSwapWidget() {
  const [sellToken, setSellToken] = useState("USDC");
  const [buyToken, setBuyToken] = useState("HYPE");
  const [sellAmount, setSellAmount] = useState("");
  const [slippage, setSlippage] = useState(2);
  const [slippagePopoverOpen, setSlippagePopoverOpen] = useState(false);

  const { executeSwap, isPending, isConnected, isWrongChain, switchToHyperEVM } =
    usePrjxSwap();

  const sellTokenMeta = getTokenBySymbol(sellToken);
  const buyTokenMeta = getTokenBySymbol(buyToken);
  const wHypeMeta = getTokenBySymbol("WHYPE");

  // Quoter sees pools as wHYPE/USDC, not native HYPE — use wHYPE address for quotes
  const tokenInForQuote = sellTokenMeta?.isNative
    ? wHypeMeta?.address
    : sellTokenMeta?.address;
  const tokenOutForQuote = buyTokenMeta?.isNative
    ? wHypeMeta?.address
    : buyTokenMeta?.address;

  const { quote, isLoading: isQuoteLoading, error: quoteError } = usePrjxQuote(
    sellAmount && parseFloat(sellAmount) > 0 && tokenInForQuote && tokenOutForQuote
      ? {
          tokenIn: tokenInForQuote,
          tokenOut: tokenOutForQuote,
          amountIn: sellAmount,
          amountInDecimals: sellTokenMeta?.decimals ?? 18,
          poolFee: 3000,
        }
      : null
  );

  const { address } = useAccount();

  // Native HYPE: use useBalance (token undefined). ERC20: use balanceOf to avoid wagmi returning wrong balance.
  const { data: nativeBalanceData, refetch: refetchNativeBalance } = useBalance({
    address: address ?? undefined,
    chainId: HYPER_EVM_CHAIN_ID,
  });

  const { data: sellErc20Balance, refetch: refetchSellBalance } = useReadContract({
    address: sellTokenMeta && !sellTokenMeta.isNative ? sellTokenMeta.address : undefined,
    abi: ERC20_BALANCE_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
  });

  const { data: buyErc20Balance, refetch: refetchBuyBalance } = useReadContract({
    address: buyTokenMeta && !buyTokenMeta.isNative ? buyTokenMeta.address : undefined,
    abi: ERC20_BALANCE_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
  });

  const refetchBalances = useCallback(() => {
    refetchNativeBalance();
    refetchSellBalance();
    refetchBuyBalance();
  }, [refetchNativeBalance, refetchSellBalance, refetchBuyBalance]);

  const sellBalance =
    sellTokenMeta?.isNative
      ? nativeBalanceData?.value
          ? parseFloat(formatUnits(nativeBalanceData.value, nativeBalanceData.decimals))
          : 0
      : sellErc20Balance !== undefined && sellTokenMeta
        ? parseFloat(formatUnits(sellErc20Balance, sellTokenMeta.decimals))
        : 0;

  const buyBalance =
    buyTokenMeta?.isNative
      ? nativeBalanceData?.value
          ? parseFloat(formatUnits(nativeBalanceData.value, nativeBalanceData.decimals))
          : 0
      : buyErc20Balance !== undefined && buyTokenMeta
        ? parseFloat(formatUnits(buyErc20Balance, buyTokenMeta.decimals))
        : 0;

  // Formatted quote (estimated buy amount) for display
  const buyAmountEstimate =
    quote !== null && quote !== undefined && buyTokenMeta
      ? formatBalance(parseFloat(formatUnits(quote, buyTokenMeta.decimals)))
      : null;
  const fiatValue = 0;

  const handleFlip = () => {
    setSellToken(buyToken);
    setBuyToken(sellToken);
    setSellAmount("");
  };

  const handleMax = () => {
    setSellAmount(String(sellBalance));
  };

  const handleHalf = () => {
    setSellAmount(String(sellBalance * 0.5));
  };

  const handleSwap = useCallback(async () => {
    if (!sellTokenMeta || !buyTokenMeta || !sellAmount || parseFloat(sellAmount) <= 0) {
      toast.error("Enter a valid amount");
      return;
    }
    if (!isConnected) {
      toast.error("Connect wallet to swap");
      return;
    }
    if (isWrongChain) {
      await switchToHyperEVM?.();
      toast.info("Switch to HyperEVM and try again");
      return;
    }

    const tokenIn =
      sellTokenMeta.isNative ? (NATIVE_HYPE_ADDRESS as Address) : sellTokenMeta.address;
    const tokenOut =
      buyTokenMeta.isNative ? (NATIVE_HYPE_ADDRESS as Address) : buyTokenMeta.address;

    // amountOutMin from Quoter with slippage tolerance (e.g. 0.5% → 99.5% of quote)
    const amountOutMin = quote
      ? (quote * BigInt(Math.floor((100 - slippage) * 100))) / 10000n
      : 0n;

    if (!quote) {
      toast.warning("No quote available — swapping with minimum output of 0. Proceed with caution.");
    }

    try {
      const tx = await executeSwap({
        tokenIn,
        tokenOut,
        amountIn: sellAmount,
        amountInDecimals: sellTokenMeta.decimals,
        amountOutMin,
        poolFee: 3000,
      });
      toast.success(`Swap submitted: ${tx}`);
      setSellAmount("");
      // Refetch balances — immediate + delayed (tx may not be in block yet)
      refetchBalances();
      setTimeout(() => refetchBalances(), 2000);
    } catch (e) {
      const err = e as { message?: string; code?: number; cause?: { message?: string } };
      const msg = err?.message ?? err?.cause?.message ?? String(e);
      const isUserReject =
        err?.code === 4001 ||
        /reject|denied|cancelled|canceled|4001|user rejected/i.test(msg);
      toast.error(isUserReject ? "User Rejected Swap" : msg);
    }
  }, [
    sellTokenMeta,
    buyTokenMeta,
    sellAmount,
    slippage,
    quote,
    isConnected,
    isWrongChain,
    switchToHyperEVM,
    executeSwap,
    refetchBalances,
  ]);

  return (
    <div className="relative flex w-full max-w-[420px] flex-col rounded-none border border-white/6 bg-[#091217]/75 shadow-top-1 backdrop-blur-xl">
      {/* Bold corner accents */}
      <div
        className="pointer-events-none absolute left-0 top-0 z-10 h-[14px] w-[14px] border-l-[3px] border-t-[3px]"
        style={{ borderColor: WIDGET_ACCENT }}
      />
      <div
        className="pointer-events-none absolute right-0 top-0 z-10 h-[14px] w-[14px] border-r-[3px] border-t-[3px]"
        style={{ borderColor: WIDGET_ACCENT }}
      />
      <div
        className="pointer-events-none absolute bottom-0 left-0 z-10 h-[14px] w-[14px] border-b-[3px] border-l-[3px]"
        style={{ borderColor: WIDGET_ACCENT }}
      />
      <div
        className="pointer-events-none absolute bottom-0 right-0 z-10 h-[14px] w-[14px] border-b-[3px] border-r-[3px]"
        style={{ borderColor: WIDGET_ACCENT }}
      />

      <div className="flex flex-col gap-0 px-4 py-4">
        {/* Sell section */}
        <div className="flex flex-col gap-3 rounded-none border border-white/4 bg-white/1 px-4 py-4">
          <span className="text-xs font-medium text-white/70">Sell</span>
          <div className="flex items-center justify-between gap-3">
            {/* Token selector */}
            <Popover>
              <PopoverTrigger asChild>
                <button
                  type="button"
                  className="relative flex items-center gap-2 rounded-none border-2 border-white/15 bg-white/5 px-3 py-2 text-sm font-medium text-white transition-colors hover:bg-white/10"
                >
                  <span className="pointer-events-none absolute left-0 top-0 h-2 w-2 border-l-2 border-t-2" style={{ borderColor: WIDGET_ACCENT }} />
                  <span className="pointer-events-none absolute right-0 top-0 h-2 w-2 border-r-2 border-t-2" style={{ borderColor: WIDGET_ACCENT }} />
                  <span className="pointer-events-none absolute bottom-0 left-0 h-2 w-2 border-b-2 border-l-2" style={{ borderColor: WIDGET_ACCENT }} />
                  <span className="pointer-events-none absolute bottom-0 right-0 h-2 w-2 border-b-2 border-r-2" style={{ borderColor: WIDGET_ACCENT }} />
                  <TokenIcon symbol={sellToken} />
                  <span>{sellToken}</span>
                  <ChevronDown size={14} className="text-white/40" />
                </button>
              </PopoverTrigger>
              <PopoverContent
                className="w-44 border-white/10 bg-[#101010]/95 p-2"
                align="start"
              >
                {SWAPABLE_SYMBOLS.filter((t) => t !== buyToken).map((t) => (
                  <button
                    key={t}
                    type="button"
                    onClick={() => {
                      setSellToken(t);
                    }}
                    className={cn(
                      "w-full rounded-none px-3 py-2 text-left text-xs transition",
                      sellToken === t
                        ? "bg-white/10 text-white"
                        : "text-white/80 hover:bg-white/5"
                    )}
                  >
                    {t}
                  </button>
                ))}
              </PopoverContent>
            </Popover>

            {/* Balance + 50% / Max */}
            <div className="flex flex-col items-end gap-1">
              <div className="flex items-center gap-2">
                <Wallet size={12} className="text-white/40" />
                <span className="text-[10px] text-white/50">{formatBalance(sellBalance)}</span>
                <button
                  type="button"
                  onClick={handleHalf}
                  className="rounded-none bg-white/5 px-2 py-0.5 text-[10px] font-medium text-white/70 hover:bg-white/10"
                >
                  50%
                </button>
                <button
                  type="button"
                  onClick={handleMax}
                  className="rounded-none bg-white/5 px-2 py-0.5 text-[10px] font-medium text-white/70 hover:bg-white/10"
                >
                  Max
                </button>
              </div>
              <div className="rounded-none border border-white/10 bg-white/2 px-3 py-2 w-full max-w-[140px]">
                <Input
                  type="number"
                  inputMode="decimal"
                  placeholder="0"
                  value={sellAmount}
                  onChange={(e) => setSellAmount(e.target.value)}
                  className="w-full min-w-0 bg-transparent text-right text-sm text-white outline-none placeholder:text-white/30"
                />
              </div>
              <span className="text-[10px] text-white/40">${fiatValue}</span>
            </div>
          </div>
        </div>

        {/* Swap direction separator */}
        <div className="relative -my-1 flex items-center justify-center">
          <div className="absolute left-0 right-0 h-px bg-white/10" />
          <button
            type="button"
            onClick={handleFlip}
            className="relative z-10 flex items-center justify-center rounded-none border border-white/10 bg-[#0E1B22] px-3 py-1.5 transition-colors hover:bg-white/5"
          >
            <ChevronDown
              size={16}
              className="rotate-0 text-white/70"
              strokeWidth={2.5}
            />
          </button>
        </div>

        {/* Buy section */}
        <div className="flex flex-col gap-3 rounded-none border border-white/4 bg-white/1 px-4 py-4">
          <span className="text-xs font-medium text-white/70">Buy</span>
          <div className="flex items-center justify-between gap-3">
            <Popover>
              <PopoverTrigger asChild>
                <button
                  type="button"
                  className="relative flex items-center gap-2 rounded-none border-2 border-white/15 bg-white/5 px-3 py-2 text-sm font-medium text-white transition-colors hover:bg-white/10"
                >
                  <span className="pointer-events-none absolute left-0 top-0 h-2 w-2 border-l-2 border-t-2" style={{ borderColor: WIDGET_ACCENT }} />
                  <span className="pointer-events-none absolute right-0 top-0 h-2 w-2 border-r-2 border-t-2" style={{ borderColor: WIDGET_ACCENT }} />
                  <span className="pointer-events-none absolute bottom-0 left-0 h-2 w-2 border-b-2 border-l-2" style={{ borderColor: WIDGET_ACCENT }} />
                  <span className="pointer-events-none absolute bottom-0 right-0 h-2 w-2 border-b-2 border-r-2" style={{ borderColor: WIDGET_ACCENT }} />
                  <TokenIcon symbol={buyToken} />
                  <span>{buyToken}</span>
                  <ChevronDown size={14} className="text-white/40" />
                </button>
              </PopoverTrigger>
              <PopoverContent
                className="w-44 border-white/10 bg-[#101010]/95 p-2"
                align="start"
              >
                {SWAPABLE_SYMBOLS.filter((t) => t !== sellToken).map((t) => (
                  <button
                    key={t}
                    type="button"
                    onClick={() => {
                      setBuyToken(t);
                    }}
                    className={cn(
                      "w-full rounded-none px-3 py-2 text-left text-xs transition",
                      buyToken === t
                        ? "bg-white/10 text-white"
                        : "text-white/80 hover:bg-white/5"
                    )}
                  >
                    {t}
                  </button>
                ))}
              </PopoverContent>
            </Popover>

            <div className="flex flex-col items-end gap-1">
              <div className="flex items-center gap-2">
                <Wallet size={12} className="text-white/40" />
                <span className="text-[10px] text-white/50">{formatBalance(buyBalance)}</span>
              </div>
              <div className="rounded-none border border-white/10 bg-white/2 px-3 py-2 w-full max-w-[140px] text-right">
                <span className="text-sm text-white/60">
                  {!sellAmount || parseFloat(sellAmount) <= 0
                    ? "—"
                    : isQuoteLoading
                      ? "..."
                      : buyAmountEstimate ?? "0"}
                </span>
              </div>
              <span className="text-[10px] text-white/40">
                {quoteError ? (
                  <span className="text-amber-400/90" title={quoteError}>{quoteError}</span>
                ) : (
                  `$${fiatValue}`
                )}
              </span>
            </div>
          </div>
        </div>

        {/* Footer: slippage + order type */}
        <div className="mt-3 flex items-center justify-between px-1">
          <Popover open={slippagePopoverOpen} onOpenChange={setSlippagePopoverOpen}>
            <PopoverTrigger asChild>
              <button
                type="button"
                className="flex items-center gap-1.5 rounded-full border border-white/10 bg-white/5 px-2.5 py-1.5 text-xs text-white/70 transition-colors hover:bg-white/10"
              >
                <Eye size={12} className="text-white/40" />
                <span>{slippage}%</span>
              </button>
            </PopoverTrigger>
            <PopoverContent
              className="w-48 border-white/10 bg-[#101010]/95 p-3"
              align="start"
            >
              <p className="mb-2 text-[10px] text-white/50">Slippage Tolerance</p>
              <div className="flex flex-col gap-1">
                {[0.5, 1, 2, 5].map((p) => (
                  <button
                    key={p}
                    type="button"
                    onClick={() => {
                      setSlippage(p);
                      setSlippagePopoverOpen(false);
                    }}
                    className={cn(
                      "w-full rounded-lg px-3 py-2 text-left text-xs transition",
                      Math.abs(slippage - p) < 0.01
                        ? "bg-white/15 text-white"
                        : "text-white/60 hover:bg-white/10"
                    )}
                  >
                    {p}%
                  </button>
                ))}
              </div>
            </PopoverContent>
          </Popover>
        </div>

        {/* Swap button */}
        <button
          type="button"
          onClick={handleSwap}
          disabled={
            !isConnected ||
            isPending ||
            !sellAmount ||
            parseFloat(sellAmount) <= 0 ||
            !sellTokenMeta ||
            !buyTokenMeta
          }
          className={cn(
            "mt-3 w-full rounded-none py-3 text-sm font-medium transition-colors",
            isConnected && sellAmount && parseFloat(sellAmount) > 0 && !isPending
              ? "bg-[#00964F]/80 hover:bg-[#00B35D] text-white"
              : "bg-white/5 text-white/40 cursor-not-allowed"
          )}
        >
          {!isConnected
            ? "Connect wallet to swap"
            : isPending
              ? "Swapping…"
              : isWrongChain
                ? "Switch to HyperEVM"
                : "Swap"}
        </button>
      </div>
    </div>
  );
}
