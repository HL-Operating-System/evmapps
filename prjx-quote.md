"use client";

import { useState, useCallback, useEffect } from "react";
import { usePublicClient } from "wagmi";
import { encodeFunctionData, decodeAbiParameters, decodeFunctionResult } from "viem";
import { parseUnits } from "viem";
import { PRJX_QUOTER_ADDRESS } from "@/constants/constants";
import { PRJX_QUOTER_ABI } from "@/lib/prjx-quoter-abi";
import { hyperEvm } from "viem/chains";
import type { Address } from "viem";

/** Quoter reverts with result. V1: 96 bytes (amount, sqrtPrice, tick). V2: 128 bytes (+ gasEstimate). May have 4-byte selector prefix. */
function decodeQuoterRevert(data: string): bigint {
  let hex = data.startsWith("0x") ? data.slice(2) : data;
  if (hex.length < 192) return 0n;
  // Strip 4-byte selector if present (8 hex chars) — some RPCs wrap revert data
  if (hex.length >= 200 && hex.length % 64 === 8) {
    hex = hex.slice(8);
  }
  const payload96 = `0x${hex.slice(0, 192)}` as `0x${string}`;
  try {
    const decoded = decodeAbiParameters(
      [{ type: "uint256" }, { type: "uint160" }, { type: "int24" }],
      payload96
    );
    return decoded[0] as bigint;
  } catch {
    // Try QuoterV2 format: 4 x uint256
    if (hex.length >= 256) {
      try {
        const payload128 = `0x${hex.slice(0, 256)}` as `0x${string}`;
        const decoded = decodeAbiParameters(
          [{ type: "uint256" }, { type: "uint256" }, { type: "uint256" }, { type: "uint256" }],
          payload128
        );
        return decoded[0] as bigint;
      } catch {
        return 0n;
      }
    }
    return 0n;
  }
}

function extractRevertData(err: unknown): string | undefined {
  let e: unknown = err;
  for (let i = 0; i < 5 && e; i++) {
    const d = (e as { data?: string })?.data;
    if (typeof d === "string" && d.length > 10) return d;
    e = (e as { cause?: unknown })?.cause;
  }
  return undefined;
}

/** WHYPE address — Quoter needs token addresses; native HYPE maps to WHYPE in pools */
const WHYPE_ADDRESS = "0x5555555555555555555555555555555555555555" as Address;

type QuoteParams = {
  tokenIn: Address;
  tokenOut: Address;
  amountIn: string;
  amountInDecimals: number;
  poolFee?: number;
};

/** Map native HYPE (0x0) to WHYPE for Quoter — pools use WHYPE */
function quoterToken(addr: Address): Address {
  return addr === "0x0000000000000000000000000000000000000000"
    ? WHYPE_ADDRESS
    : addr;
}

/**
 * Fetches expected amountOut from Project X Quoter.
 * Used for slippage protection (amountOutMin = quote * (1 - slippage/100))
 */
export function usePrjxQuote(params: QuoteParams | null) {
  const { tokenIn, tokenOut, amountIn, amountInDecimals, poolFee = 3000 } =
    params ?? { tokenIn: "0x" as Address, tokenOut: "0x" as Address, amountIn: "", amountInDecimals: 18 };

  const publicClient = usePublicClient({ chainId: hyperEvm.id });
  const [quote, setQuote] = useState<bigint | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchQuote = useCallback(async () => {
    if (!amountIn || parseFloat(amountIn) <= 0 || !publicClient || tokenIn === "0x" || tokenOut === "0x") {
      setQuote(null);
      return;
    }

    setIsLoading(true);
    setError(null);

    const tokenInResolved = quoterToken(tokenIn);
    const tokenOutResolved = quoterToken(tokenOut);
    try {
      const amountInWei = parseUnits(amountIn, amountInDecimals);
      const calldata = encodeFunctionData({
        abi: PRJX_QUOTER_ABI,
        functionName: "quoteExactInputSingle",
        args: [
          {
            tokenIn: tokenInResolved,
            tokenOut: tokenOutResolved,
            amountIn: amountInWei,
            fee: poolFee,
            sqrtPriceLimitX96: 0n,
          },
        ],
      });

      const result = await publicClient.call({
        to: PRJX_QUOTER_ADDRESS,
        data: calldata,
      });

      // HyperEVM Quoter returns result (doesn't revert like Uniswap's)
      if (result?.data && typeof result.data === "string") {
        const decoded = decodeFunctionResult({
          abi: PRJX_QUOTER_ABI,
          functionName: "quoteExactInputSingle",
          data: result.data as `0x${string}`,
        });
        const amountOut = Array.isArray(decoded) ? decoded[0] : (decoded as unknown as { amountOut: bigint }).amountOut;
        if (amountOut > 0n) {
          setQuote(amountOut);
          setError(null);
        } else {
          setQuote(null);
        }
      } else {
        setQuote(null);
      }
    } catch (e: unknown) {
      const revertData = extractRevertData(e);
      const msg = e instanceof Error ? e.message : String(e);

      if (revertData && typeof revertData === "string" && revertData.length > 10) {
        const amountOut = decodeQuoterRevert(revertData);
        if (amountOut > 0n) {
          setQuote(amountOut);
          setError(null);
        } else {
          setError(msg.length > 80 ? msg.slice(0, 80) + "…" : msg);
          setQuote(null);
        }
      } else {
        setError(msg.length > 80 ? msg.slice(0, 80) + "…" : msg);
        setQuote(null);
      }
    } finally {
      setIsLoading(false);
    }
  }, [amountIn, amountInDecimals, poolFee, tokenIn, tokenOut, publicClient]);

  useEffect(() => {
    fetchQuote();
  }, [fetchQuote]);

  return { quote, isLoading: isLoading, error, refetch: fetchQuote };
}
