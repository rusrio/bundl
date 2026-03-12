// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BundlHook} from "./BundlHook.sol";

/// @title BundlRouter
/// @notice Generic sell router for any BundlHook index.
///
/// @dev One deployment serves all BundlHook instances.
///      The caller passes `hookAddress` per call; the router reads
///      `indexToken()` and `usdc()` dynamically from that hook.
///
/// @dev Sell flow:
///   1. transferFrom(user → router, indexAmount)        outside unlock
///   2. unlock()
///      a. sync(IndexToken) + transfer(router → PM) + settle()
///         → PM records +indexAmount IndexToken credit for router
///      b. swap() → hook.beforeSwap (_handleSell):
///           - take(IndexToken, hook, indexToBurn)  PM: 0
///           - burn + sell underlyings → USDC stays in PM
///           - specifiedDelta = +indexToBurn, unspecifiedDelta = -usdcOut
///           → router now has a positive USDC delta in PM
///      c. Read router's USDC delta via TransientStateLibrary
///      d. take(USDC, user, usdcOut)   PM USDC: 0
///   Both PM balances = 0 at unlock close ✓
contract BundlRouter is IUnlockCallback {
    using SafeERC20 for IERC20;
    using TransientStateLibrary for IPoolManager;

    error NotPoolManager();
    error InsufficientOutput();
    error NoUsdcReceived();

    IPoolManager public immutable poolManager;

    struct CallbackData {
        PoolKey  key;
        address  hookAddress;
        uint256  indexAmount;
        address  user;
        uint256  minUsdcOut;
    }

    constructor(IPoolManager _pm) {
        poolManager = _pm;
    }

    // ─────────────────────────────── SELL ───────────────────────────────

    /// @notice Sell exact `indexAmount` of any BundlHook IndexToken for USDC.
    /// @param key          The (IndexToken, USDC) pool key for this index
    /// @param hookAddress  The BundlHook that manages this index
    /// @param indexAmount  Exact amount of IndexToken to sell (18 dec)
    /// @param minUsdcOut   Minimum USDC to receive (slippage guard)
    function sellIndex(
        PoolKey calldata key,
        address hookAddress,
        uint256 indexAmount,
        uint256 minUsdcOut
    ) external returns (uint256 usdcReceived) {
        BundlHook hook = BundlHook(hookAddress);

        IERC20(address(hook.indexToken())).safeTransferFrom(
            msg.sender,
            address(this),
            indexAmount
        );

        bytes memory result = poolManager.unlock(
            abi.encode(CallbackData({
                key:         key,
                hookAddress: hookAddress,
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
        BundlHook hook = BundlHook(p.hookAddress);

        address indexTokenAddr = address(hook.indexToken());
        address usdcAddr       = hook.usdc();

        // ── Step 1: Deposit IndexToken into PM ──────────────────────────
        // Creates a positive delta (credit) for the router on IndexToken.
        poolManager.sync(Currency.wrap(indexTokenAddr));
        IERC20(indexTokenAddr).safeTransfer(address(poolManager), p.indexAmount);
        poolManager.settle();

        // ── Step 2: Swap → triggers hook._handleSell ─────────────────────
        // The hook will:
        //   - take IndexToken from PM (clears router's IndexToken credit)
        //   - burn + sell underlyings → USDC remains in PM
        //   - return specifiedDelta=+indexToBurn, unspecifiedDelta=-usdcOut
        //     which gives the router a positive USDC delta in PM
        bool indexIsCurrency0 =
            Currency.unwrap(p.key.currency0) == indexTokenAddr;
        bool zeroForOne = indexIsCurrency0;

        poolManager.swap(
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

        // ── Step 3: Read router's actual USDC credit from transient state ─
        // With beforeSwapReturnDelta the BalanceDelta returned by swap() to
        // the caller is the *net* of pool + hook deltas and can be misleading.
        // currencyDelta() always returns the true outstanding credit/debt for
        // this address: positive = PM owes us tokens.
        int256 usdcCredit = poolManager.currencyDelta(
            address(this),
            Currency.wrap(usdcAddr)
        );

        if (usdcCredit <= 0) revert NoUsdcReceived();
        uint256 usdcOut = uint256(usdcCredit);

        if (usdcOut < p.minUsdcOut) revert InsufficientOutput();

        // ── Step 4: Deliver USDC to user ─────────────────────────────────
        poolManager.take(Currency.wrap(usdcAddr), p.user, usdcOut);

        return abi.encode(usdcOut);
    }
}
