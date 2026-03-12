// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BundlHook} from "./BundlHook.sol";

/// @title BundlRouter
/// @notice Minimal sell router for BundlHook.
///
/// @dev Sell flow:
///   1. transferFrom(user → router, indexAmount)   outside unlock
///   2. unlock()
///      a. sync(IndexToken) + transfer(router → PM) + settle()
///         → PM records +indexAmount IndexToken
///      b. swap() → hook.beforeSwap:
///           - take(IndexToken, hook, indexToBurn)  PM: 0
///           - burn + sell underlyings → USDC in PM
///           - specifiedDelta = +indexToBurn, unspecifiedDelta = -usdcOut
///      c. take(USDC, user, usdcOut)  PM USDC: 0
///   Both PM balances = 0 at unlock close ✓
contract BundlRouter is IUnlockCallback {
    using SafeERC20 for IERC20;

    error NotPoolManager();
    error InsufficientOutput();

    IPoolManager public immutable poolManager;
    BundlHook    public immutable hook;

    struct CallbackData {
        PoolKey  key;
        uint256  indexAmount;
        address  user;
        uint256  minUsdcOut;
    }

    constructor(IPoolManager _pm, BundlHook _hook) {
        poolManager = _pm;
        hook        = _hook;
    }

    // ─────────────────────────────── SELL ───────────────────────────────

    /// @notice Sell exact `indexAmount` IndexToken for USDC.
    /// @dev    User must approve this router for IndexToken.
    function sellIndex(
        PoolKey calldata key,
        uint256 indexAmount,
        uint256 minUsdcOut
    ) external returns (uint256 usdcReceived) {
        // Pull IndexToken from user to this router before entering unlock.
        // Inside unlockCallback we will deposit them into PM.
        IERC20(address(hook.indexToken())).safeTransferFrom(
            msg.sender,
            address(this),
            indexAmount
        );

        bytes memory result = poolManager.unlock(
            abi.encode(CallbackData({
                key:         key,
                indexAmount: indexAmount,
                user:        msg.sender,
                minUsdcOut:  minUsdcOut
            }))
        );

        usdcReceived = abi.decode(result, (uint256));
    }

    // ─────────────────────────────── UNLOCK CALLBACK ───────────────────────────────

    function unlockCallback(bytes calldata data)
        external override returns (bytes memory)
    {
        if (msg.sender != address(poolManager)) revert NotPoolManager();

        CallbackData memory p = abi.decode(data, (CallbackData));

        IERC20 indexERC20 = IERC20(address(hook.indexToken()));

        // ── Step 1: Deposit IndexToken into PM ──────────────────────────
        // sync() snapshots PM's current IndexToken balance.
        // Then we transfer from router → PM.
        // settle() computes the difference → PM records +indexAmount.
        poolManager.sync(Currency.wrap(address(hook.indexToken())));
        indexERC20.safeTransfer(address(poolManager), p.indexAmount);
        poolManager.settle();
        // PM IndexToken balance: +indexAmount

        // ── Step 2: Swap (triggers hook.beforeSwap / _handleSell) ───────
        // zeroForOne = true  if IndexToken is currency0 (index → usdc)
        // zeroForOne = false if IndexToken is currency1 (usdc ← index)
        bool indexIsCurrency0 =
            Currency.unwrap(p.key.currency0) == address(hook.indexToken());
        bool zeroForOne = indexIsCurrency0;

        // hookData = abi.encode(user) so _handleSell knows who to attribute
        BalanceDelta delta = poolManager.swap(
            p.key,
            IPoolManager.SwapParams({
                zeroForOne:        zeroForOne,
                amountSpecified:   -int256(p.indexAmount),
                sqrtPriceLimitX96: zeroForOne
                    ? TickMath.MIN_SQRT_PRICE + 1
                    : TickMath.MAX_SQRT_PRICE - 1
            }),
            abi.encode(p.user)
        );
        // After beforeSwap:
        //   IndexToken: +deposit - take(hook) + specifiedDelta(+) = 0
        //   USDC:       +sellUnderlyings (hook deposited into PM)

        // ── Step 3: Take USDC for user ──────────────────────────────────
        int128 usdcDelta = indexIsCurrency0
            ? delta.amount1()   // USDC is currency1
            : delta.amount0();  // USDC is currency0

        // usdcDelta is negative: PM owes us USDC (hook deposited it)
        uint256 usdcOut = uint128(usdcDelta < 0 ? -usdcDelta : usdcDelta);

        if (usdcOut < p.minUsdcOut) revert InsufficientOutput();

        poolManager.take(
            Currency.wrap(address(hook.usdc())),
            p.user,
            usdcOut
        );
        // PM USDC balance: 0 ✓

        return abi.encode(usdcOut);
    }
}
