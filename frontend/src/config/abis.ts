// DollarStore contract ABI
export const dollarStoreABI = [
  // View functions
  {
    name: "getReserves",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "stablecoins", type: "address[]" },
      { name: "amounts", type: "uint256[]" },
    ],
  },
  {
    name: "getReserve",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "stablecoin", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "supportedStablecoins",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address[]" }],
  },
  {
    name: "isSupported",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "stablecoin", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "dlrsToken",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    name: "getQueueDepth",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "stablecoin", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "getQueuePosition",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "positionId", type: "uint256" }],
    outputs: [
      { name: "owner", type: "address" },
      { name: "stablecoin", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "timestamp", type: "uint256" },
    ],
  },
  {
    name: "getUserQueuePositions",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "positionIds", type: "uint256[]" }],
  },
  {
    name: "getQueuePositionInfo",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "positionId", type: "uint256" }],
    outputs: [
      { name: "amountAhead", type: "uint256" },
      { name: "positionNumber", type: "uint256" },
    ],
  },
  // Write functions
  {
    name: "deposit",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "stablecoin", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "dlrsMinted", type: "uint256" }],
  },
  {
    name: "withdraw",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "stablecoin", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "stablecoinReceived", type: "uint256" }],
  },
  {
    name: "joinQueue",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "stablecoin", type: "address" },
      { name: "dlrsAmount", type: "uint256" },
    ],
    outputs: [{ name: "positionId", type: "uint256" }],
  },
  {
    name: "cancelQueue",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "positionId", type: "uint256" }],
    outputs: [{ name: "dlrsReturned", type: "uint256" }],
  },
  {
    name: "swap",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "fromStablecoin", type: "address" },
      { name: "toStablecoin", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "queueIfUnavailable", type: "bool" },
    ],
    outputs: [
      { name: "received", type: "uint256" },
      { name: "positionId", type: "uint256" },
    ],
  },
  {
    name: "swapFromDLRS",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "toStablecoin", type: "address" },
      { name: "dlrsAmount", type: "uint256" },
      { name: "queueIfUnavailable", type: "bool" },
    ],
    outputs: [
      { name: "received", type: "uint256" },
      { name: "positionId", type: "uint256" },
    ],
  },
  // Events
  {
    name: "Deposit",
    type: "event",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "stablecoin", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "dlrsMinted", type: "uint256", indexed: false },
    ],
  },
  {
    name: "Withdraw",
    type: "event",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "stablecoin", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "dlrsBurned", type: "uint256", indexed: false },
    ],
  },
] as const;

// CENTS token ABI
export const centsABI = [
  // View functions
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "stakedBalance",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "stakeTimestamp",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "unstakeInitiated",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "getStakePower",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "getDailyFeeFreeCap",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "dailyRedemptionUsed",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "getStakingInfo",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [
      { name: "staked", type: "uint256" },
      { name: "stakePower", type: "uint256" },
      { name: "stakedSince", type: "uint256" },
      { name: "unstakeTime", type: "uint256" },
      { name: "isUnstaking", type: "bool" },
    ],
  },
  {
    name: "getEmissionStats",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "makerRemaining", type: "uint256" },
      { name: "takerRemaining", type: "uint256" },
      { name: "founderVested", type: "uint256" },
      { name: "totalMinted", type: "uint256" },
    ],
  },
  {
    name: "totalSupply",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "FULL_POWER_DURATION",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "UNSTAKE_COOLDOWN",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "allowance",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
  // Write functions
  {
    name: "approve",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "stake",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
  },
  {
    name: "unstake",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [],
  },
  {
    name: "completeUnstake",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [],
  },
  {
    name: "cancelUnstake",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [],
  },
  // Events
  {
    name: "Staked",
    type: "event",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "newStakePower", type: "uint256", indexed: false },
    ],
  },
  {
    name: "UnstakeInitiated",
    type: "event",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "completionTime", type: "uint256", indexed: false },
    ],
  },
  {
    name: "UnstakeCompleted",
    type: "event",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
  {
    name: "UnstakeCancelled",
    type: "event",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
] as const;

// Standard ERC20 ABI (for USDC, USDT, DLRS)
export const erc20ABI = [
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "allowance",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "approve",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "transfer",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "decimals",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    name: "symbol",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
  },
  {
    name: "totalSupply",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;
