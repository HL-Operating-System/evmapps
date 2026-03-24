// Kinetiq protocol — contract addresses and ABI fragments for kHYPE liquid staking

export const KINETIQ_CONTRACTS = {
  KHYPE_TOKEN: "0xfD739d4e423301CE9385c1fb8850539D657C296D" as const,
  STAKING_ACCOUNTANT: "0x9209648Ec9D448EF57116B73A2f081835643dc7A" as const,
  STAKING_MANAGER: "0x393D0B87Ed38fc779FD9611144aE649BA6082109" as const,
  VALIDATOR_MANAGER: "0x4b797A93DfC3D18Cf98B7322a2b142FA8007508f" as const,
} as const;

export const KHYPE_ABI = [
  {
    inputs: [{ name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "totalSupply",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    name: "approve",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;

export const STAKING_ACCOUNTANT_ABI = [
  {
    inputs: [{ name: "HYPEAmount", type: "uint256" }],
    name: "HYPEToKHYPE",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "kHYPEAmount", type: "uint256" }],
    name: "kHYPEToHYPE",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

export const STAKING_MANAGER_ABI = [
  {
    inputs: [],
    name: "stake",
    outputs: [],
    stateMutability: "payable",
    type: "function",
  },
  {
    inputs: [{ name: "amount", type: "uint256" }],
    name: "queueWithdrawal",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ name: "withdrawalId", type: "uint256" }],
    name: "confirmWithdrawal",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { name: "user", type: "address" },
      { name: "id", type: "uint256" },
    ],
    name: "withdrawalRequests",
    outputs: [
      {
        components: [
          { name: "hypeAmount", type: "uint256" },
          { name: "kHYPEAmount", type: "uint256" },
          { name: "kHYPEFee", type: "uint256" },
          { name: "bufferUsed", type: "uint256" },
          { name: "timestamp", type: "uint256" },
        ],
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "user", type: "address" }],
    name: "nextWithdrawalId",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "minStakeAmount",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "maxStakeAmount",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "withdrawalDelay",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "unstakeFeeRate",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "totalStaked",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

/** Map contract revert messages to user-friendly strings */
export function handleContractError(error: unknown): string {
  const msg = (error as { message?: string })?.message ?? String(error);
  if (msg.includes("insufficient funds")) return "Insufficient HYPE balance for transaction";
  if (msg.includes("Below minimum stake")) return "Stake amount is below the minimum required";
  if (msg.includes("Above maximum stake")) return "Stake amount exceeds the maximum allowed";
  if (msg.includes("Would exceed staking limit")) return "This stake would exceed the protocol limit";
  if (msg.includes("Withdrawal delay not met")) return "Withdrawal is still in the delay period";
  if (/reject|denied|cancelled|canceled|user rejected|4001/i.test(msg)) return "Transaction rejected";
  return msg || "Transaction failed";
}
