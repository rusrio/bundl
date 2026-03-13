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
    const zeroForOne = c0.toLowerCase() === usdc.toLowerCase();

    const key = { currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: BUNDL_HOOK_ADDRESS };

    const MIN_SQRT_PRICE = 4295128739n;
    const MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342n;

    const params = {
      zeroForOne,
      amountSpecified: -amountIn,
      sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE + 1n : MAX_SQRT_PRICE - 1n,
    };

    const testSettings = { takeClaims: false, settleUsingBurn: false };
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
// SELL: IndexToken → USDC via BundlRouter.sellIndex(key, indexAmount, minUsdc)
//
// Uses two separate useWriteContract instances so approve and sellIndex
// each have independent hash/state — prevents MetaMask from skipping
// the second popup when both share the same wagmi write hook.
// ---------------------------------------------------------------------------
export function useSellIndex() {
  const { writeContractAsync: sellAsync, data: sellHash, isPending: isSellPending, error } = useWriteContract();
  const publicClient = usePublicClient();
  const { address } = useAccount();

  const sell = async (
    indexTokenAddress: `0x${string}`,
    hookAddress: `0x${string}`,
    indexAmount: bigint,
    minUsdc: bigint = 0n,
  ) => {
    if (!address) throw new Error('Wallet not connected');

    const usdc = USDC_ADDRESS;
    const c0 = indexTokenAddress.toLowerCase() < usdc.toLowerCase() ? indexTokenAddress : usdc;
    const c1 = indexTokenAddress.toLowerCase() < usdc.toLowerCase() ? usdc             : indexTokenAddress;
    const key = { currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: hookAddress };

    // Step: sell — 4 args: key, hookAddress, indexAmount, minUsdc
    const txHash = await sellAsync({
      address: BUNDL_ROUTER_ADDRESS,
      abi: BUNDL_ROUTER_ABI,
      functionName: 'sellIndex',
      args: [key, hookAddress, indexAmount, minUsdc],
    });

    await publicClient!.waitForTransactionReceipt({ hash: txHash });
    return txHash;
  };

  const { isLoading: isWaiting, isSuccess } = useWaitForTransactionReceipt({ hash: sellHash });
  return { sell, isPending: isSellPending || isWaiting, error, isSuccess };
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
