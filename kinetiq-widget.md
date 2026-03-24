"use client";

import { useState, useCallback, useEffect, useMemo } from "react";
import { ArrowDownUp, Loader2, Clock, Check } from "lucide-react";
import { cn } from "@/lib/utils";
import Input from "@/components/shared/input";
import { useAccount, useBalance, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { formatUnits, parseEther, formatEther } from "viem";
import { toast } from "sonner";
import {
  KINETIQ_CONTRACTS,
  KHYPE_ABI,
  STAKING_ACCOUNTANT_ABI,
  STAKING_MANAGER_ABI,
  handleContractError,
} from "@/lib/kinetiq";

const HYPER_EVM_CHAIN_ID = 999;
const WIDGET_ACCENT = "#7EC9C8";

function formatBal(value: number): string {
  if (value >= 1e9) return value.toExponential(2);
  if (value >= 1e6) return value.toLocaleString("en-US", { maximumFractionDigits: 2 });
  if (value >= 1) return value.toLocaleString("en-US", { minimumFractionDigits: 0, maximumFractionDigits: 4 });
  if (value > 0) return value.toFixed(6);
  return "0";
}

function formatDuration(seconds: number): string {
  if (seconds <= 0) return "Ready";
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

interface PendingWithdrawal {
  id: bigint;
  hypeAmount: bigint;
  kHYPEAmount: bigint;
  kHYPEFee: bigint;
  timestamp: bigint;
  ready: boolean;
  timeRemaining: number;
}

export default function KinetiqWidget() {
  const [mode, setMode] = useState<"stake" | "unstake">("stake");
  const [amount, setAmount] = useState("");
  const [pendingWithdrawals, setPendingWithdrawals] = useState<PendingWithdrawal[]>([]);

  const { address, isConnected } = useAccount();

  // ── Balances ──────────────────────────────────────────────────────────

  const { data: nativeBalance, refetch: refetchNative } = useBalance({
    address: address ?? undefined,
    chainId: HYPER_EVM_CHAIN_ID,
  });

  const { data: kHypeBalanceRaw, refetch: refetchKhype } = useReadContract({
    address: KINETIQ_CONTRACTS.KHYPE_TOKEN,
    abi: KHYPE_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    chainId: HYPER_EVM_CHAIN_ID,
  });

  // ── Exchange rates ────────────────────────────────────────────────────

  const parsedAmount = amount && parseFloat(amount) > 0 ? parseEther(amount) : 0n;

  const { data: kHypeEstimate } = useReadContract({
    address: KINETIQ_CONTRACTS.STAKING_ACCOUNTANT,
    abi: STAKING_ACCOUNTANT_ABI,
    functionName: "HYPEToKHYPE",
    args: parsedAmount > 0n && mode === "stake" ? [parsedAmount] : undefined,
    chainId: HYPER_EVM_CHAIN_ID,
  });

  const { data: hypeEstimate } = useReadContract({
    address: KINETIQ_CONTRACTS.STAKING_ACCOUNTANT,
    abi: STAKING_ACCOUNTANT_ABI,
    functionName: "kHYPEToHYPE",
    args: parsedAmount > 0n && mode === "unstake" ? [parsedAmount] : undefined,
    chainId: HYPER_EVM_CHAIN_ID,
  });

  const { data: rateFor1Hype } = useReadContract({
    address: KINETIQ_CONTRACTS.STAKING_ACCOUNTANT,
    abi: STAKING_ACCOUNTANT_ABI,
    functionName: "HYPEToKHYPE",
    args: [parseEther("1")],
    chainId: HYPER_EVM_CHAIN_ID,
  });

  // ── Protocol info ─────────────────────────────────────────────────────

  const { data: minStake } = useReadContract({
    address: KINETIQ_CONTRACTS.STAKING_MANAGER,
    abi: STAKING_MANAGER_ABI,
    functionName: "minStakeAmount",
    chainId: HYPER_EVM_CHAIN_ID,
  });

  const { data: maxStake } = useReadContract({
    address: KINETIQ_CONTRACTS.STAKING_MANAGER,
    abi: STAKING_MANAGER_ABI,
    functionName: "maxStakeAmount",
    chainId: HYPER_EVM_CHAIN_ID,
  });

  const { data: totalStaked } = useReadContract({
    address: KINETIQ_CONTRACTS.STAKING_MANAGER,
    abi: STAKING_MANAGER_ABI,
    functionName: "totalStaked",
    chainId: HYPER_EVM_CHAIN_ID,
  });

  const { data: withdrawalDelay } = useReadContract({
    address: KINETIQ_CONTRACTS.STAKING_MANAGER,
    abi: STAKING_MANAGER_ABI,
    functionName: "withdrawalDelay",
    chainId: HYPER_EVM_CHAIN_ID,
  });

  const { data: unstakeFeeRate } = useReadContract({
    address: KINETIQ_CONTRACTS.STAKING_MANAGER,
    abi: STAKING_MANAGER_ABI,
    functionName: "unstakeFeeRate",
    chainId: HYPER_EVM_CHAIN_ID,
  });

  // ── Pending withdrawals ───────────────────────────────────────────────

  const { data: nextWithdrawalId } = useReadContract({
    address: KINETIQ_CONTRACTS.STAKING_MANAGER,
    abi: STAKING_MANAGER_ABI,
    functionName: "nextWithdrawalId",
    args: address ? [address] : undefined,
    chainId: HYPER_EVM_CHAIN_ID,
  });

  // Fetch last 10 withdrawal requests
  const withdrawalIdsToCheck = useMemo(() => {
    if (!nextWithdrawalId || nextWithdrawalId === 0n) return [];
    const ids: bigint[] = [];
    const start = nextWithdrawalId > 10n ? nextWithdrawalId - 10n : 0n;
    for (let i = start; i < nextWithdrawalId; i++) {
      ids.push(i);
    }
    return ids;
  }, [nextWithdrawalId]);

  // Read each withdrawal request — we use individual hooks for the first 3
  const { data: wr0 } = useReadContract({
    address: KINETIQ_CONTRACTS.STAKING_MANAGER,
    abi: STAKING_MANAGER_ABI,
    functionName: "withdrawalRequests",
    args: address && withdrawalIdsToCheck[0] !== undefined ? [address, withdrawalIdsToCheck[0]] : undefined,
    chainId: HYPER_EVM_CHAIN_ID,
  });
  const { data: wr1 } = useReadContract({
    address: KINETIQ_CONTRACTS.STAKING_MANAGER,
    abi: STAKING_MANAGER_ABI,
    functionName: "withdrawalRequests",
    args: address && withdrawalIdsToCheck[1] !== undefined ? [address, withdrawalIdsToCheck[1]] : undefined,
    chainId: HYPER_EVM_CHAIN_ID,
  });
  const { data: wr2 } = useReadContract({
    address: KINETIQ_CONTRACTS.STAKING_MANAGER,
    abi: STAKING_MANAGER_ABI,
    functionName: "withdrawalRequests",
    args: address && withdrawalIdsToCheck[2] !== undefined ? [address, withdrawalIdsToCheck[2]] : undefined,
    chainId: HYPER_EVM_CHAIN_ID,
  });
  const { data: wr3 } = useReadContract({
    address: KINETIQ_CONTRACTS.STAKING_MANAGER,
    abi: STAKING_MANAGER_ABI,
    functionName: "withdrawalRequests",
    args: address && withdrawalIdsToCheck[3] !== undefined ? [address, withdrawalIdsToCheck[3]] : undefined,
    chainId: HYPER_EVM_CHAIN_ID,
  });
  const { data: wr4 } = useReadContract({
    address: KINETIQ_CONTRACTS.STAKING_MANAGER,
    abi: STAKING_MANAGER_ABI,
    functionName: "withdrawalRequests",
    args: address && withdrawalIdsToCheck[4] !== undefined ? [address, withdrawalIdsToCheck[4]] : undefined,
    chainId: HYPER_EVM_CHAIN_ID,
  });

  // Build pending withdrawals from results
  useEffect(() => {
    const rawResults = [wr0, wr1, wr2, wr3, wr4];
    const delay = withdrawalDelay ?? 0n;
    const now = BigInt(Math.floor(Date.now() / 1000));
    const items: PendingWithdrawal[] = [];

    for (let i = 0; i < rawResults.length; i++) {
      const r = rawResults[i];
      if (!r || withdrawalIdsToCheck[i] === undefined) continue;
      const { hypeAmount, kHYPEAmount, kHYPEFee, timestamp } = r as { hypeAmount: bigint; kHYPEAmount: bigint; kHYPEFee: bigint; bufferUsed: bigint; timestamp: bigint };
      if (timestamp === 0n) continue;
      const confirmTime = timestamp + delay;
      const ready = now >= confirmTime;
      const timeRemaining = ready ? 0 : Number(confirmTime - now);
      items.push({
        id: withdrawalIdsToCheck[i],
        hypeAmount,
        kHYPEAmount,
        kHYPEFee,
        timestamp,
        ready,
        timeRemaining,
      });
    }
    setPendingWithdrawals(items);
  }, [wr0, wr1, wr2, wr3, wr4, withdrawalIdsToCheck, withdrawalDelay]);

  // Tick down timers
  useEffect(() => {
    if (pendingWithdrawals.length === 0 || pendingWithdrawals.every((w) => w.ready)) return;
    const interval = setInterval(() => {
      setPendingWithdrawals((prev) =>
        prev.map((w) => {
          if (w.ready) return w;
          const remaining = Math.max(0, w.timeRemaining - 60);
          return { ...w, timeRemaining: remaining, ready: remaining <= 0 };
        })
      );
    }, 60_000);
    return () => clearInterval(interval);
  }, [pendingWithdrawals]);

  // ── Write contracts ───────────────────────────────────────────────────

  const { writeContract: writeStake, data: stakeTxHash, isPending: isStakePending } = useWriteContract();
  const { writeContract: writeApprove, data: approveTxHash, isPending: isApprovePending } = useWriteContract();
  const { writeContract: writeQueue, data: queueTxHash, isPending: isQueuePending } = useWriteContract();
  const { writeContract: writeConfirm, data: confirmTxHash, isPending: isConfirmPending } = useWriteContract();

  const { isLoading: isStakeConfirming } = useWaitForTransactionReceipt({ hash: stakeTxHash });
  const { isLoading: isApproveConfirming } = useWaitForTransactionReceipt({ hash: approveTxHash });
  const { isLoading: isQueueConfirming } = useWaitForTransactionReceipt({ hash: queueTxHash });
  const { isLoading: isConfirmConfirming } = useWaitForTransactionReceipt({ hash: confirmTxHash });

  // ── Derived values ────────────────────────────────────────────────────

  const hypeBalance = nativeBalance?.value
    ? parseFloat(formatUnits(nativeBalance.value, nativeBalance.decimals))
    : 0;

  const kHypeBalance = kHypeBalanceRaw !== undefined
    ? parseFloat(formatUnits(kHypeBalanceRaw, 18))
    : 0;

  const currentBalance = mode === "stake" ? hypeBalance : kHypeBalance;

  const outputEstimate =
    mode === "stake"
      ? kHypeEstimate !== undefined ? formatBal(parseFloat(formatUnits(kHypeEstimate, 18))) : null
      : hypeEstimate !== undefined ? formatBal(parseFloat(formatUnits(hypeEstimate, 18))) : null;

  const exchangeRate = rateFor1Hype !== undefined
    ? parseFloat(formatUnits(rateFor1Hype, 18)).toFixed(4)
    : "—";

  const feePercent = unstakeFeeRate !== undefined ? Number(unstakeFeeRate) / 100 : null;
  const delayHours = withdrawalDelay !== undefined ? Number(withdrawalDelay) / 3600 : null;

  const refetchBalances = useCallback(() => {
    refetchNative();
    refetchKhype();
  }, [refetchNative, refetchKhype]);

  const handleMax = () => setAmount(String(currentBalance));
  const handleHalf = () => setAmount(String(currentBalance * 0.5));

  // Validate stake amount against protocol limits
  const stakeValidation = useMemo(() => {
    if (!amount || parseFloat(amount) <= 0) return null;
    const parsed = parseEther(amount);
    if (minStake !== undefined && parsed < minStake) {
      return `Min stake: ${formatBal(parseFloat(formatEther(minStake)))} HYPE`;
    }
    if (maxStake !== undefined && parsed > maxStake) {
      return `Max stake: ${formatBal(parseFloat(formatEther(maxStake)))} HYPE`;
    }
    return null;
  }, [amount, minStake, maxStake]);

  // ── Handlers ──────────────────────────────────────────────────────────

  const handleStake = useCallback(() => {
    if (!amount || parseFloat(amount) <= 0 || !isConnected) return;
    if (stakeValidation) { toast.error(stakeValidation); return; }
    try {
      writeStake({
        address: KINETIQ_CONTRACTS.STAKING_MANAGER,
        abi: STAKING_MANAGER_ABI,
        functionName: "stake",
        value: parseEther(amount),
        chainId: HYPER_EVM_CHAIN_ID,
      });
      toast.success("Stake transaction submitted");
      setAmount("");
      refetchBalances();
      setTimeout(() => refetchBalances(), 3000);
    } catch (e) {
      toast.error(handleContractError(e));
    }
  }, [amount, isConnected, stakeValidation, writeStake, refetchBalances]);

  const handleQueueWithdrawal = useCallback(() => {
    if (!amount || parseFloat(amount) <= 0 || !isConnected) return;
    const kHypeAmt = parseEther(amount);

    // First approve kHYPE spend, then queue
    try {
      writeApprove({
        address: KINETIQ_CONTRACTS.KHYPE_TOKEN,
        abi: KHYPE_ABI,
        functionName: "approve",
        args: [KINETIQ_CONTRACTS.STAKING_MANAGER, kHypeAmt],
        chainId: HYPER_EVM_CHAIN_ID,
      }, {
        onSuccess: () => {
          writeQueue({
            address: KINETIQ_CONTRACTS.STAKING_MANAGER,
            abi: STAKING_MANAGER_ABI,
            functionName: "queueWithdrawal",
            args: [kHypeAmt],
            chainId: HYPER_EVM_CHAIN_ID,
          });
          toast.success("Withdrawal queued");
          setAmount("");
          refetchBalances();
          setTimeout(() => refetchBalances(), 3000);
        },
      });
    } catch (e) {
      toast.error(handleContractError(e));
    }
  }, [amount, isConnected, writeApprove, writeQueue, refetchBalances]);

  const handleConfirmWithdrawal = useCallback((withdrawalId: bigint) => {
    try {
      writeConfirm({
        address: KINETIQ_CONTRACTS.STAKING_MANAGER,
        abi: STAKING_MANAGER_ABI,
        functionName: "confirmWithdrawal",
        args: [withdrawalId],
        chainId: HYPER_EVM_CHAIN_ID,
      });
      toast.success("Withdrawal confirmed");
      refetchBalances();
      setTimeout(() => refetchBalances(), 3000);
    } catch (e) {
      toast.error(handleContractError(e));
    }
  }, [writeConfirm, refetchBalances]);

  const handleSubmit = mode === "stake" ? handleStake : handleQueueWithdrawal;

  const isLoading =
    isStakePending || isStakeConfirming ||
    isApprovePending || isApproveConfirming ||
    isQueuePending || isQueueConfirming;

  const isConfirmLoading = isConfirmPending || isConfirmConfirming;

  return (
    <div className="relative flex w-full max-w-[420px] flex-col overflow-y-auto rounded-none border border-white/6 bg-[#091217]/75 shadow-top-1 backdrop-blur-xl">
      {/* Corner accents */}
      <div className="pointer-events-none absolute left-0 top-0 z-10 h-[14px] w-[14px] border-l-[3px] border-t-[3px]" style={{ borderColor: WIDGET_ACCENT }} />
      <div className="pointer-events-none absolute right-0 top-0 z-10 h-[14px] w-[14px] border-r-[3px] border-t-[3px]" style={{ borderColor: WIDGET_ACCENT }} />
      <div className="pointer-events-none absolute bottom-0 left-0 z-10 h-[14px] w-[14px] border-b-[3px] border-l-[3px]" style={{ borderColor: WIDGET_ACCENT }} />
      <div className="pointer-events-none absolute bottom-0 right-0 z-10 h-[14px] w-[14px] border-b-[3px] border-r-[3px]" style={{ borderColor: WIDGET_ACCENT }} />

      <div className="flex flex-col gap-0 px-4 py-4">
        {/* Mode tabs */}
        <div className="mb-4 flex rounded-none border border-white/8 bg-white/2">
          <button
            type="button"
            onClick={() => { setMode("stake"); setAmount(""); }}
            className={cn(
              "flex-1 py-2 text-xs font-medium transition-colors",
              mode === "stake"
                ? "bg-[#7EC9C8]/15 text-[#7EC9C8]"
                : "text-white/40 hover:text-white/60"
            )}
          >
            Stake
          </button>
          <button
            type="button"
            onClick={() => { setMode("unstake"); setAmount(""); }}
            className={cn(
              "flex-1 py-2 text-xs font-medium transition-colors",
              mode === "unstake"
                ? "bg-[#7EC9C8]/15 text-[#7EC9C8]"
                : "text-white/40 hover:text-white/60"
            )}
          >
            Unstake
          </button>
        </div>

        {/* Balance overview */}
        {isConnected && (
          <div className="mb-3 flex items-center justify-between rounded-none border border-white/4 bg-white/1 px-4 py-2.5">
            <div className="flex flex-col gap-0.5">
              <span className="text-[10px] text-white/40">HYPE Balance</span>
              <span className="text-xs font-medium text-white/70">{formatBal(hypeBalance)}</span>
            </div>
            <div className="h-6 w-px bg-white/8" />
            <div className="flex flex-col items-end gap-0.5">
              <span className="text-[10px] text-white/40">kHYPE Balance</span>
              <span className="text-xs font-medium text-[#7EC9C8]/80">{formatBal(kHypeBalance)}</span>
            </div>
          </div>
        )}

        {/* Input section */}
        <div className="flex flex-col gap-3 rounded-none border border-white/4 bg-white/1 px-4 py-4">
          <span className="text-xs font-medium text-white/70">
            {mode === "stake" ? "You stake" : "You unstake"}
          </span>
          <div className="flex items-center justify-between gap-3">
            <div className="relative flex items-center gap-2 rounded-none border-2 border-white/15 bg-white/5 px-3 py-2 text-sm font-medium text-white">
              <span className="pointer-events-none absolute left-0 top-0 h-2 w-2 border-l-2 border-t-2" style={{ borderColor: WIDGET_ACCENT }} />
              <span className="pointer-events-none absolute right-0 top-0 h-2 w-2 border-r-2 border-t-2" style={{ borderColor: WIDGET_ACCENT }} />
              <span className="pointer-events-none absolute bottom-0 left-0 h-2 w-2 border-b-2 border-l-2" style={{ borderColor: WIDGET_ACCENT }} />
              <span className="pointer-events-none absolute bottom-0 right-0 h-2 w-2 border-b-2 border-r-2" style={{ borderColor: WIDGET_ACCENT }} />
              <div className={cn(
                "flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-sm font-semibold text-white",
                mode === "stake" ? "bg-[#7EC9C8]/30" : "bg-[#5B8DEF]/30"
              )}>
                {mode === "stake" ? "H" : "K"}
              </div>
              <span>{mode === "stake" ? "HYPE" : "kHYPE"}</span>
            </div>

            <div className="flex flex-col items-end gap-1">
              <div className="flex items-center gap-2">
                <button type="button" onClick={handleHalf} className="rounded-none bg-white/5 px-2 py-0.5 text-[10px] font-medium text-white/70 hover:bg-white/10">
                  50%
                </button>
                <button type="button" onClick={handleMax} className="rounded-none bg-white/5 px-2 py-0.5 text-[10px] font-medium text-white/70 hover:bg-white/10">
                  Max
                </button>
              </div>
              <div className="rounded-none border border-white/10 bg-white/2 px-3 py-2 w-full max-w-[140px]">
                <Input
                  type="number"
                  inputMode="decimal"
                  placeholder="0"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  className="w-full min-w-0 bg-transparent text-right text-sm text-white outline-none placeholder:text-white/30"
                />
              </div>
              {stakeValidation && mode === "stake" && (
                <span className="text-[10px] text-amber-400/90">{stakeValidation}</span>
              )}
            </div>
          </div>
        </div>

        {/* Arrow separator */}
        <div className="relative -my-1 flex items-center justify-center">
          <div className="absolute left-0 right-0 h-px bg-white/10" />
          <div className="relative z-10 flex items-center justify-center rounded-none border border-white/10 bg-[#0E1B22] px-3 py-1.5">
            <ArrowDownUp size={16} className="text-white/70" strokeWidth={2.5} />
          </div>
        </div>

        {/* Output section */}
        <div className="flex flex-col gap-3 rounded-none border border-white/4 bg-white/1 px-4 py-4">
          <span className="text-xs font-medium text-white/70">You receive</span>
          <div className="flex items-center justify-between gap-3">
            <div className="relative flex items-center gap-2 rounded-none border-2 border-white/15 bg-white/5 px-3 py-2 text-sm font-medium text-white">
              <span className="pointer-events-none absolute left-0 top-0 h-2 w-2 border-l-2 border-t-2" style={{ borderColor: WIDGET_ACCENT }} />
              <span className="pointer-events-none absolute right-0 top-0 h-2 w-2 border-r-2 border-t-2" style={{ borderColor: WIDGET_ACCENT }} />
              <span className="pointer-events-none absolute bottom-0 left-0 h-2 w-2 border-b-2 border-l-2" style={{ borderColor: WIDGET_ACCENT }} />
              <span className="pointer-events-none absolute bottom-0 right-0 h-2 w-2 border-b-2 border-r-2" style={{ borderColor: WIDGET_ACCENT }} />
              <div className={cn(
                "flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-sm font-semibold text-white",
                mode === "stake" ? "bg-[#5B8DEF]/30" : "bg-[#7EC9C8]/30"
              )}>
                {mode === "stake" ? "K" : "H"}
              </div>
              <span>{mode === "stake" ? "kHYPE" : "HYPE"}</span>
            </div>

            <div className="flex flex-col items-end gap-1">
              <div className="rounded-none border border-white/10 bg-white/2 px-3 py-2 w-full max-w-[140px] text-right">
                <span className="text-sm text-white/60">
                  {!amount || parseFloat(amount) <= 0 ? "—" : outputEstimate ?? "..."}
                </span>
              </div>
            </div>
          </div>
        </div>

        {/* Protocol info row */}
        <div className="mt-3 flex flex-col gap-1 px-1">
          <div className="flex items-center justify-between">
            <span className="text-[10px] text-white/40">Exchange Rate</span>
            <span className="text-[10px] text-white/50">1 HYPE = {exchangeRate} kHYPE</span>
          </div>
          {mode === "unstake" && feePercent !== null && (
            <div className="flex items-center justify-between">
              <span className="text-[10px] text-white/40">Unstake Fee</span>
              <span className="text-[10px] text-white/50">{feePercent}%</span>
            </div>
          )}
          {mode === "unstake" && delayHours !== null && (
            <div className="flex items-center justify-between">
              <span className="text-[10px] text-white/40">Withdrawal Delay</span>
              <span className="text-[10px] text-white/50">{delayHours}h</span>
            </div>
          )}
          {totalStaked !== undefined && (
            <div className="flex items-center justify-between">
              <span className="text-[10px] text-white/40">Total Staked</span>
              <span className="text-[10px] text-white/50">{formatBal(parseFloat(formatEther(totalStaked)))} HYPE</span>
            </div>
          )}
        </div>

        {/* Submit button */}
        <button
          type="button"
          onClick={handleSubmit}
          disabled={!isConnected || isLoading || !amount || parseFloat(amount) <= 0 || (mode === "stake" && !!stakeValidation)}
          className={cn(
            "mt-3 flex w-full items-center justify-center gap-2 rounded-none py-3 text-sm font-medium transition-colors",
            isConnected && amount && parseFloat(amount) > 0 && !isLoading && !(mode === "stake" && stakeValidation)
              ? "bg-[#7EC9C8]/30 hover:bg-[#7EC9C8]/50 text-[#7EC9C8]"
              : "bg-white/5 text-white/40 cursor-not-allowed"
          )}
        >
          {isLoading && <Loader2 size={14} className="animate-spin" />}
          {!isConnected
            ? "Connect wallet"
            : isLoading
              ? "Processing…"
              : mode === "stake"
                ? "Stake HYPE"
                : "Queue Withdrawal"}
        </button>

        {/* Pending withdrawals */}
        {mode === "unstake" && pendingWithdrawals.length > 0 && (
          <div className="mt-4 flex flex-col gap-2">
            <span className="text-[10px] font-medium text-white/50">Pending Withdrawals</span>
            {pendingWithdrawals.map((w) => (
              <div
                key={w.id.toString()}
                className="flex items-center justify-between rounded-none border border-white/6 bg-white/2 px-3 py-2"
              >
                <div className="flex flex-col gap-0.5">
                  <span className="text-[11px] text-white/70">
                    {formatBal(parseFloat(formatEther(w.hypeAmount)))} HYPE
                  </span>
                  <span className="flex items-center gap-1 text-[10px] text-white/40">
                    <Clock size={10} />
                    {w.ready ? (
                      <span className="text-[#7EC9C8]">Ready to claim</span>
                    ) : (
                      formatDuration(w.timeRemaining)
                    )}
                  </span>
                  {w.kHYPEFee > 0n && (
                    <span className="text-[9px] text-white/30">
                      Fee: {formatBal(parseFloat(formatEther(w.kHYPEFee)))} kHYPE
                    </span>
                  )}
                </div>
                {w.ready && (
                  <button
                    type="button"
                    onClick={() => handleConfirmWithdrawal(w.id)}
                    disabled={isConfirmLoading}
                    className="flex items-center gap-1 rounded-none bg-[#7EC9C8]/20 px-2.5 py-1.5 text-[10px] font-medium text-[#7EC9C8] transition-colors hover:bg-[#7EC9C8]/40"
                  >
                    {isConfirmLoading ? <Loader2 size={10} className="animate-spin" /> : <Check size={10} />}
                    Claim
                  </button>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
