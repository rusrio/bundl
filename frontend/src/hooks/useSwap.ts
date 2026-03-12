import { useWriteContract, useWaitForTransactionReceipt, useAccount, usePublicClient } from 'wagmi';
import {
  BUNDL_HOOK_ADDRESS,
  BUNDL_HOOK_ABI,
  BUNDL_TOKEN_ADDRESS,
  USDC_ADDRESS,
  ERC20_ABI,
  V4_ROUTER_ADDRESS,
  V4_ROUTER_ABI,
  BUNDL_ROUTER_ADDRESS,
  BUNDL_ROUTER_ABI,
} from '../config/contracts';
import { encodeAbiParameters, parseAbiParameters } from 'viem';

// ---------------------------------------------------------------------------
// Approve any ERC-20 token for a given spender
// ---------------------------------------------------------------------------
export function useApproveToken(tokenAddress: `0x${string}`, spender?: `0x${string}`) {
  const { writeContractAsync, data: hash, isPending, error } = useWriteContract();
  const publicClient = usePublicClient();

  const approve = async (amount: bigint, overrideSpender?: `0x${string}`) => {
    const target = overrideSpender ?? spender ?? V4_ROUTER_ADDRESS;
    const txHash = await writeContractAsync({
      address: tokenAddress,
      abi: ERC20_ABI,
      functionName: 'approve',
      args: [target, amount],
    });
    await publicClient!.waitForTransactionReceipt({ hash: txHash });
    return txHash;
  };

  const { isLoading: isWaiting, isSuccess } = useWaitForTransactionReceipt({ hash });

  return { approve, isPending: isPending || isWaiting, isSuccess, error };
}

// ---------------------------------------------------------------------------
// BUY: USDC → IndexToken via PoolSwapTest (v4 test router)
// ---------------------------------------------------------------------------
export function useSwapExactInput() {
  const { writeContractAsync, data: hash, isPending, error } = useWriteContract();
  const publicClient = usePublicClient();
  const { address } = useAccount();

  const swap = async (amountIn: bigint, minOutput: bigint = 0n) => {
    if (!address) throw new Error('Wallet not connected');

    const usdc       = USDC_ADDRESS;
    const indexToken = BUNDL_TOKEN_ADDRESS;

    const c0 = indexToken.toLowerCase() < usdc.toLowerCase() ? indexToken : usdc;
    const c1 = indexToken.toLowerCase() < usdc.toLowerCase() ? usdc       : indexToken;
    // Buy = USDC → IndexToken.
    // zeroForOne = true  if USDC is currency0 (paying USDC to get IndexToken)
    // zeroForOne = false if USDC is currency1
    const zeroForOne = c0.toLowerCase() === usdc.toLowerCase();

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
      amountSpecified: -amountIn,  // exact-in: negative
      sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE + 1n : MAX_SQRT_PRICE - 1n,
    };

    const testSettings = { takeClaims: false, settleUsingBurn: false };
    // hookData for buy = abi.encode(uint256 minOutput)
    const hookData = encodeAbiParameters(parseAbiParameters('uint256'), [minOutput]);

    const txHash = await writeContractAsync({
      address: V4_ROUTER_ADDRESS,
      abi: V4_ROUTER_ABI,
      functionName: 'swap',
      args: [key, params, testSettings, hookData],
    });
    await publicClient!.waitForTransactionReceipt({ hash: txHash });
    return txHash;
  };

  const { isLoading: isWaiting, isSuccess } = useWaitForTransactionReceipt({ hash });

  return { swap, isPending: isPending || isWaiting, error, isSuccess };
}

// ---------------------------------------------------------------------------
// SELL: IndexToken → USDC via BundlRouter.sellIndex()
//
// Flow:
//   1. approve(BundlRouter, indexAmount)     ← user approves BundlRouter
//   2. sellIndex(key, indexAmount, minUsdc)  ← router handles deposit+swap+take
// ---------------------------------------------------------------------------
export function useSellIndex() {
  const { writeContractAsync, data: hash, isPending, error } = useWriteContract();
  const publicClient = usePublicClient();
  const { address } = useAccount();

  const sell = async (indexAmount: bigint, minUsdc: bigint = 0n) => {
    if (!address) throw new Error('Wallet not connected');

    const usdc       = USDC_ADDRESS;
    const indexToken = BUNDL_TOKEN_ADDRESS;

    const c0 = indexToken.toLowerCase() < usdc.toLowerCase() ? indexToken : usdc;
    const c1 = indexToken.toLowerCase() < usdc.toLowerCase() ? usdc       : indexToken;

    const key = {
      currency0: c0,
      currency1: c1,
      fee: 3000,
      tickSpacing: 60,
      hooks: BUNDL_HOOK_ADDRESS,
    };

    // Step 1: approve BundlRouter to pull IndexToken
    const approveTx = await writeContractAsync({
      address: indexToken,
      abi: ERC20_ABI,
      functionName: 'approve',
      args: [BUNDL_ROUTER_ADDRESS, indexAmount],
    });
    await publicClient!.waitForTransactionReceipt({ hash: approveTx });

    // Step 2: sell via BundlRouter
    const txHash = await writeContractAsync({
      address: BUNDL_ROUTER_ADDRESS,
      abi: BUNDL_ROUTER_ABI,
      functionName: 'sellIndex',
      args: [key, indexAmount, minUsdc],
    });
    await publicClient!.waitForTransactionReceipt({ hash: txHash });
    return txHash;
  };

  const { isLoading: isWaiting, isSuccess } = useWaitForTransactionReceipt({ hash });

  return { sell, isPending: isPending || isWaiting, error, isSuccess };
}

// ---------------------------------------------------------------------------
// REDEEM: burn IndexToken → receive underlying assets (WBTC + WETH)
// ---------------------------------------------------------------------------
export function useRedeemIndex() {
  const { writeContractAsync, data: hash, isPending, error } = useWriteContract();
  const publicClient = usePublicClient();

  const redeem = async (units: bigint) => {
    const txHash = await writeContractAsync({
      address: BUNDL_HOOK_ADDRESS,
      abi: BUNDL_HOOK_ABI,
      functionName: 'redeem',
      args: [units],
    });
    await publicClient!.waitForTransactionReceipt({ hash: txHash });
    return txHash;
  };

  const { isLoading: isWaiting, isSuccess } = useWaitForTransactionReceipt({ hash });

  return { redeem, isPending: isPending || isWaiting, isSuccess, error };
}
