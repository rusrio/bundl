import { useReadContract } from 'wagmi';
import { BUNDL_HOOK_ADDRESS, BUNDL_HOOK_ABI } from '../config/contracts';

export function useUnderlyingTokens() {
  return useReadContract({
    address: BUNDL_HOOK_ADDRESS,
    abi: BUNDL_HOOK_ABI,
    functionName: 'getUnderlyingTokens',
  });
}

export function useAmountsPerUnit() {
  return useReadContract({
    address: BUNDL_HOOK_ADDRESS,
    abi: BUNDL_HOOK_ABI,
    functionName: 'getAmountsPerUnit',
  });
}

export function useTotalBacking() {
  return useReadContract({
    address: BUNDL_HOOK_ADDRESS,
    abi: BUNDL_HOOK_ABI,
    functionName: 'getTotalBacking',
  });
}

export function usePoolStates() {
  return useReadContract({
    address: BUNDL_HOOK_ADDRESS,
    abi: BUNDL_HOOK_ABI,
    functionName: 'getPoolStates',
  });
}

export function useNavPerUnit() {
  return useReadContract({
    address: BUNDL_HOOK_ADDRESS,
    abi: BUNDL_HOOK_ABI,
    functionName: 'getNavPerUnit',
  });
}

/// Returns bool[] indicating whether USDC is currency0 for each underlying pool.
/// Used by the frontend to correctly interpret sqrtPriceX96 spot prices.
export function useUsdcIs0() {
  return useReadContract({
    address: BUNDL_HOOK_ADDRESS,
    abi: BUNDL_HOOK_ABI,
    functionName: 'getUsdcIs0',
  });
}
