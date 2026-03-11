import { useWriteContract, useWaitForTransactionReceipt, useAccount } from 'wagmi';
import { BUNDL_HOOK_ADDRESS, BUNDL_HOOK_ABI, BUNDL_TOKEN_ADDRESS, USDC_ADDRESS, ERC20_ABI, V4_ROUTER_ADDRESS, V4_ROUTER_ABI } from '../config/contracts';
import { encodeAbiParameters, parseAbiParameters } from 'viem';

export function useApproveToken(tokenAddress: `0x${string}`) {
  const { writeContractAsync, data: hash, isPending, error } = useWriteContract();
  
  const approve = async (amount: bigint) => {
    return writeContractAsync({
      address: tokenAddress,
      abi: ERC20_ABI,
      functionName: 'approve',
      args: [V4_ROUTER_ADDRESS, amount],
    });
  };

  const { isLoading: isWaiting, isSuccess } = useWaitForTransactionReceipt({ hash });

  return { approve, isPending: isPending || isWaiting, isSuccess, error };
}

export function useSwapExactInput() {
  const { writeContractAsync, data: hash, isPending, error } = useWriteContract();
  const { address } = useAccount();
  
  const swap = async (amountIn: bigint, isBuy: boolean = true, minOutput: bigint = 0n) => {
    if (!address) throw new Error("Wallet not connected");

    const usdc = USDC_ADDRESS;
    const indexToken = BUNDL_TOKEN_ADDRESS;

    // Currency sorting for PoolKey
    const c0 = indexToken.toLowerCase() < usdc.toLowerCase() ? indexToken : usdc;
    const c1 = indexToken.toLowerCase() < usdc.toLowerCase() ? usdc : indexToken;
    
    // Determine SWAP direction
    // If c0 is IndexToken, isBuy (buying index w/ USDC) means we are swapping c1 -> c0 (zeroForOne = false)
    const zeroForOne = c0.toLowerCase() === indexToken.toLowerCase() ? !isBuy : isBuy;

    const key = {
      currency0: c0,
      currency1: c1,
      fee: 3000,
      tickSpacing: 60,
      hooks: BUNDL_HOOK_ADDRESS
    };

    const MIN_SQRT_PRICE = 4295128739n;
    const MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342n;

    const params = {
      zeroForOne: zeroForOne,
      amountSpecified: -amountIn, // Exact input is represented as negative
      sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE + 1n : MAX_SQRT_PRICE - 1n
    };

    const testSettings = {
      takeClaims: false,
      settleUsingBurn: false
    };

    const hookData = encodeAbiParameters(parseAbiParameters('uint256'), [minOutput]);

    return writeContractAsync({
      address: V4_ROUTER_ADDRESS,
      abi: V4_ROUTER_ABI,
      functionName: 'swap',
      args: [key, params, testSettings, hookData],
    });
  };

  const { isLoading: isWaiting, isSuccess } = useWaitForTransactionReceipt({ hash });

  return { swap, isPending: isPending || isWaiting, error, isSuccess };
}

export function useRedeemIndex() {
  const { writeContractAsync, data: hash, isPending, error } = useWriteContract();
  
  const redeem = async (units: bigint) => {
    return writeContractAsync({
      address: BUNDL_HOOK_ADDRESS,
      abi: BUNDL_HOOK_ABI,
      functionName: 'redeem',
      args: [units],
    });
  };

  const { isLoading: isWaiting, isSuccess } = useWaitForTransactionReceipt({ hash });

  return { redeem, isPending: isPending || isWaiting, isSuccess, error };
}
