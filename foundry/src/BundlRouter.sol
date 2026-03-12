// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BundlHook} from "./BundlHook.sol";

/// @title BundlRouter
/// @notice Minimal swap router for BundlHook that correctly handles the sell flow.
///
/// @dev Why a custom router?
///   PoolSwapTest unconditionally settles both sides of a swap after beforeSwap.
///   For the sell flow, BundlHook handles IndexToken entirely out-of-band:
///   it burns tokens directly from its own balance (transferred here before the swap)
///   and re-deposits USDC into PM via the underlying swap primitives.
///   After beforeSwap, PM's net IndexToken balance is 0 and USDC is already there.
///   A custom router allows us to:
///     1. Transfer IndexToken from user to hook BEFORE entering unlock
///     2. Inside unlockCallback: run the swap (which triggers beforeSwap/burn/sell)
///     3. Only settle USDC — skip IndexToken settlement entirely
///     4. Deliver USDC to user via take()
contract BundlRouter is IUnlockCallback {
    using SafeERC20 for IERC20;

    error NotPoolManager();
    error OnlyBuy();

    IPoolManager public immutable poolManager;
    BundlHook    public immutable hook;

    struct SellCallbackData {
        PoolKey   key;
        address   user;
        uint256   indexAmount;
        bool      indexIsCurrency0;
        address   usdc;
    }

    constructor(IPoolManager _poolManager, BundlHook _hook) {
        poolManager = _poolManager;
        hook        = _hook;
    }

    // ─────────────────────────── SELL ───────────────────────────

    /// @notice Sell exact `indexAmount` of IndexToken for USDC.
    /// @param key          The (IndexToken, USDC) pool key
    /// @param indexAmount  Exact amount of IndexToken to sell (18 dec)
    /// @param minUsdc      Minimum USDC to receive (slippage guard)
    function sellIndex(
        PoolKey calldata key,
        uint256 indexAmount,
        uint256 minUsdc
    ) external returns (uint256 usdcReceived) {
        // Transfer IndexToken from user to hook BEFORE entering unlock.
        // Hook will burn them inside beforeSwap.
        IERC20(address(hook.indexToken())).safeTransferFrom(
            msg.sender,
            address(hook),
            indexAmount
        );

        bool indexIsCurrency0 = Currency.unwrap(key.currency0) == address(hook.indexToken());

        bytes memory result = poolManager.unlock(
            abi.encode(SellCallbackData({
                key:              key,
                user:             msg.sender,
                indexAmount:      indexAmount,
                indexIsCurrency0: indexIsCurrency0,
                usdc:             hook.usdc()
            }))
        );

        usdcReceived = abi.decode(result, (uint256));
        require(usdcReceived >= minUsdc, "BundlRouter: insufficient output");
    }

    // ─────────────────────────── UNLOCK CALLBACK ───────────────────────────

    function unlockCallback(bytes calldata data)
        external override returns (bytes memory)
    {
        if (msg.sender != address(poolManager)) revert NotPoolManager();

        SellCallbackData memory d = abi.decode(data, (SellCallbackData));

        // zeroForOne: selling IndexToken for USDC
        //   if index is currency0 → zeroForOne = true  (index → usdc)
        //   if index is currency1 → zeroForOne = false (usdc ← index)
        bool zeroForOne = d.indexIsCurrency0;

        uint160 sqrtPriceLimit = zeroForOne
            ? 4295128740          // MIN_SQRT_PRICE + 1
            : 1461446703485210103287273052203988822378723970341; // MAX_SQRT_PRICE - 1

        // Run the swap. beforeSwap fires here:
        //   - hook burns IndexToken (already sitting in hook from pre-transfer)
        //   - hook sells underlyings → re-deposits USDC into PM
        //   - specifiedDelta = +indexAmount  (amountToSwap = 0)
        //   - unspecifiedDelta = -usdcReceived
        // After this call:
        //   - PM's IndexToken net balance = 0 (hook never deposited it)
        //   - PM's USDC net balance = +usdcReceived (hook deposited it)
        BalanceDelta delta = poolManager.swap(
            d.key,
            IPoolManager.SwapParams({
                zeroForOne:        zeroForOne,
                amountSpecified:   -int256(d.indexAmount),
                sqrtPriceLimitX96: sqrtPriceLimit
            }),
            abi.encode(d.user)
        );

        // Extract USDC amount from delta.
        // unspecifiedDelta = -usdcReceived was set by hook, so PM owes user USDC.
        // delta.amount0/1 for USDC side is negative (PM gives USDC out).
        int128 usdcDelta = d.indexIsCurrency0 ? delta.amount1() : delta.amount0();
        uint256 usdcOut  = uint256(uint128(usdcDelta < 0 ? -usdcDelta : usdcDelta));

        // Deliver USDC to user.
        // PM has it from the hook's _swapExactUnderlyingForUsdc re-deposit.
        poolManager.take(Currency.wrap(d.usdc), d.user, usdcOut);

        // IndexToken side: PM balance = 0, nothing to settle.
        // USDC side: we just took it, nothing else to settle.

        return abi.encode(usdcOut);
    }
}
