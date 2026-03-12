import { parseAbi } from 'viem';

export const BUNDL_HOOK_ADDRESS    = (process.env.NEXT_PUBLIC_BUNDL_HOOK_ADDRESS    || '0x00') as `0x${string}`;
export const BUNDL_TOKEN_ADDRESS   = (process.env.NEXT_PUBLIC_BUNDL_TOKEN_ADDRESS   || '0x00') as `0x${string}`;
export const USDC_ADDRESS          = (process.env.NEXT_PUBLIC_USDC_ADDRESS          || '0x00') as `0x${string}`;
export const V4_ROUTER_ADDRESS     = (process.env.NEXT_PUBLIC_V4_ROUTER_ADDRESS     || '0x00') as `0x${string}`;
export const BUNDL_ROUTER_ADDRESS  = (process.env.NEXT_PUBLIC_BUNDL_ROUTER_ADDRESS  || '0x00') as `0x${string}`;

export const BUNDL_HOOK_ABI = parseAbi([
  'function getUnderlyingTokens() external view returns (address[] memory)',
  'function getAmountsPerUnit() external view returns (uint256[] memory)',
  'function getTotalBacking() external view returns (uint256[] memory)',
  'function getPoolStates() external view returns (uint160[] memory sqrtPrices, int24[] memory ticks, uint128[] memory liquidities)',
  'function getNavPerUnit() external view returns (uint256 navPerUnit)',
  'function getUsdcIs0() external view returns (bool[] memory)',
  'function getSpotPrice(uint256 tokenIndex) external view returns (uint256 spotPriceUsdc)',
  'function getSpotPrices() external view returns (uint256[] memory spotPricesUsdc)',
  'function redeem(uint256 units) external',
]);

export const BUNDL_TOKEN_ABI = parseAbi([
  'function balanceOf(address account) external view returns (uint256)',
  'function totalSupply() external view returns (uint256)',
  'function decimals() external view returns (uint8)',
  'function symbol() external view returns (string)',
]);

export const ERC20_ABI = parseAbi([
  'function balanceOf(address account) external view returns (uint256)',
  'function allowance(address owner, address spender) external view returns (uint256)',
  'function approve(address spender, uint256 amount) external returns (bool)',
  'function decimals() external view returns (uint8)',
  'function symbol() external view returns (string)',
]);

export const V4_ROUTER_ABI = parseAbi([
  'struct PoolKey { address currency0; address currency1; uint24 fee; int24 tickSpacing; address hooks; }',
  'struct SwapParams { bool zeroForOne; int256 amountSpecified; uint160 sqrtPriceLimitX96; }',
  'struct TestSettings { bool takeClaims; bool settleUsingBurn; }',
  'function swap(PoolKey calldata key, SwapParams calldata params, TestSettings calldata testSettings, bytes calldata hookData) external payable returns (int256 delta)',
]);

// BundlRouter — the hook address is immutable in the router constructor,
// so sellIndex only needs: key, indexAmount, minUsdc.
export const BUNDL_ROUTER_ABI = parseAbi([
  'struct PoolKey { address currency0; address currency1; uint24 fee; int24 tickSpacing; address hooks; }',
  'function sellIndex(PoolKey calldata key, uint256 indexAmount, uint256 minUsdc) external returns (uint256 usdcReceived)',
]);
