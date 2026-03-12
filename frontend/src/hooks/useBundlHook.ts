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

export function useUsdcIs0() {
  return useReadContract({
    address: BUNDL_HOOK_ADDRESS,
    abi: BUNDL_HOOK_ABI,
    functionName: 'getUsdcIs0',
  });
}

/// Returns spot prices (in USDC, 6 decimals) for all underlying tokens in one call.
/// This is the canonical source for spot prices — no math needed in the frontend.
export function useSpotPrices() {
  return useReadContract({
    address: BUNDL_HOOK_ADDRESS,
    abi: BUNDL_HOOK_ABI,
    functionName: 'getSpotPrices',
  });
}
