import { useReadContract } from 'wagmi';
import { BUNDL_TOKEN_ADDRESS, BUNDL_TOKEN_ABI, USDC_ADDRESS, ERC20_ABI } from '../config/contracts';

export function useIndexBalance(address?: `0x${string}`) {
  return useReadContract({
    address: BUNDL_TOKEN_ADDRESS,
    abi: BUNDL_TOKEN_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    }
  });
}

export function useIndexTotalSupply() {
  return useReadContract({
    address: BUNDL_TOKEN_ADDRESS,
    abi: BUNDL_TOKEN_ABI,
    functionName: 'totalSupply',
  });
}

export function useUsdcBalance(address?: `0x${string}`) {
  return useReadContract({
    address: USDC_ADDRESS,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    }
  });
}
export function useTokenAllowance(tokenAddress: `0x${string}`, owner?: `0x${string}`, spender?: `0x${string}`) {
  return useReadContract({
    address: tokenAddress,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: owner && spender ? [owner, spender] : undefined,
    query: {
      enabled: !!owner && !!spender,
    }
  });
}
