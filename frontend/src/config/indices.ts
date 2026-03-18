export interface BundlIndex {
  id: string
  name: string
  symbol: string
  hookAddress: `0x${string}`
  tokenAddress: `0x${string}`
  weights: { symbol: string; bps: number }[]
}

export const INDICES: BundlIndex[] = [
  {
    id: 'bBLUE',
    name: 'Blue Chip DeFi',
    symbol: 'bBLUE',
    hookAddress:  (process.env.NEXT_PUBLIC_BUNDL_HOOK_ADDRESS  || '0x0000000000000000000000000000000000000000') as `0x${string}`,
    tokenAddress: (process.env.NEXT_PUBLIC_BUNDL_TOKEN_ADDRESS || '0x0000000000000000000000000000000000000000') as `0x${string}`,
    weights: [
      { symbol: 'BTC', bps: 5000 },
      { symbol: 'ETH', bps: 5000 },
    ],
  },
  {
    id: 'bBEU',
    name: 'BTC-ETH-UNI Index',
    symbol: 'bBEU',
    hookAddress:  (process.env.NEXT_PUBLIC_BUNDL_HOOK2_ADDRESS  || '0x0000000000000000000000000000000000000000') as `0x${string}`,
    tokenAddress: (process.env.NEXT_PUBLIC_BUNDL_TOKEN2_ADDRESS || '0x0000000000000000000000000000000000000000') as `0x${string}`,
    weights: [
      { symbol: 'BTC', bps: 4000 },
      { symbol: 'ETH', bps: 3000 },
      { symbol: 'UNI', bps: 3000 },
    ],
  },
]
