import { useWriteContract, useWaitForTransactionReceipt, useAccount, usePublicClient } from 'wagmi';
import { BUNDL_HOOK_ADDRESS, BUNDL_HOOK_ABI, BUNDL_TOKEN_ADDRESS, USDC_ADDRESS, ERC20_ABI, V4_ROUTER_ADDRESS, V4_ROUTER_ABI } from '../config/contracts';
import { encodeAbiParameters, parseAbiParameters } from 'viem';

export function useApproveToken(tokenAddress: `0x${string}`) {
  const { writeContractAsync, data: hash, isPending, error } = useWriteContract();
  const publicClient = usePublicClient();

  const approve = async (amount: bigint) => {
    const hash = await writeContractAsync({
      address: tokenAddress,
      abi: ERC20_ABI,
      functionName: 'approve',
      args: [V4_ROUTER_ADDRESS, amount],
    });
    // Wait for the approval to be mined before returning
    await publicClient!.waitForTransactionReceipt({ hash });
    return hash;
  };

  const { isLoading: isWaiting, isSuccess } = useWaitForTransactionReceipt({ hash });

  return { approve, isPending: isPending || isWaiting, isSuccess, error };
}

export function useSwapExactInput() {
  const { writeContractAsync, data: hash, isPending, error } = useWriteContract();
  const publicClient = usePublicClient();
  const { address } = useAccount();

  const swap = async (amountIn: bigint, isBuy: boolean = true, minOutput: bigint = 0n) => {
    if (!address) throw new Error('Wallet not connected');

    const usdc = USDC_ADDRESS;
    const indexToken = BUNDL_TOKEN_ADDRESS;

    const c0 = indexToken.toLowerCase() < usdc.toLowerCase() ? indexToken : usdc;
    const c1 = indexToken.toLowerCase() < usdc.toLowerCase() ? usdc : indexToken;
    const zeroForOne = c0.toLowerCase() === indexToken.toLowerCase() ? !isBuy : isBuy;

    const key = {
      currency0: c0,
      currency1: c1,
      fee: 3000,
      tickSpacing: 60,
      hooks: BUNDL_HOOK_ADDRESS,
    };

    const MIN_SQRT_PRICE = 4295128739n;
    const MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342n;

    const params = {
      zeroForOne,
      amountSpecified: -amountIn,
      sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE + 1n : MAX_SQRT_PRICE - 1n,
    };

    const testSettings = { takeClaims: false, settleUsingBurn: false };
    const hookData = encodeAbiParameters(parseAbiParameters('uint256'), [minOutput]);

    const hash = await writeContractAsync({
      address: V4_ROUTER_ADDRESS,
      abi: V4_ROUTER_ABI,
      functionName: 'swap',
      args: [key, params, testSettings, hookData],
    });
    // Wait for swap to be mined
    await publicClient!.waitForTransactionReceipt({ hash });
    return hash;
  };

  const { isLoading: isWaiting, isSuccess } = useWaitForTransactionReceipt({ hash });

  return { swap, isPending: isPending || isWaiting, error, isSuccess };
}

export function useRedeemIndex() {
  const { writeContractAsync, data: hash, isPending, error } = useWriteContract();
  const publicClient = usePublicClient();

  const redeem = async (units: bigint) => {
    const hash = await writeContractAsync({
      address: BUNDL_HOOK_ADDRESS,
      abi: BUNDL_HOOK_ABI,
      functionName: 'redeem',
      args: [units],
    });
    await publicClient!.waitForTransactionReceipt({ hash });
    return hash;
  };

  const { isLoading: isWaiting, isSuccess } = useWaitForTransactionReceipt({ hash });

  return { redeem, isPending: isPending || isWaiting, isSuccess, error };
}
