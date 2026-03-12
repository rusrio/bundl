// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

import {BundlToken} from "./BundlToken.sol";
import {IBundlHook} from "./interfaces/IBundlHook.sol";

/// @title BundlHook
/// @notice Uniswap v4 hook — NAV-priced market maker for index tokens.
///
/// @dev BeforeSwapDelta sign convention (v4):
///   Positive delta  = hook RECEIVES that token from the PM
///   Negative delta  = hook GIVES that token to the PM
///   PM computes: amountToSwap = params.amountSpecified + specifiedDelta
///   To bypass the pool entirely: specifiedDelta = -params.amountSpecified
///
/// @dev BUY flow (USDC → IndexToken), exact-in (amountSpecified = -usdcIn):
///   specifiedDelta   = +usdcIn    hook takes USDC from PM (PM settles it from user)
///   unspecifiedDelta = -indexOut  hook gives IndexToken to PM (PM delivers to user)
///   amountToSwap = -usdcIn + usdcIn = 0 → pool untouched
///
/// @dev SELL flow (IndexToken → USDC), exact-in (amountSpecified = -indexIn):
///   1. User transfers IndexToken to hook
///   2. Hook deposits IndexToken into PM (sync+transfer+settle)
///   3. Hook takes IndexToken from PM and burns it
///   4. Hook sells underlyings → re-deposits USDC into PM
///   specifiedDelta   = +indexIn   hook takes IndexToken from PM (offsets amountToSwap)
///   unspecifiedDelta = -usdcOut   hook gives USDC to PM (PM delivers to user)
///   amountToSwap = -indexIn + indexIn = 0 → pool untouched
contract BundlHook is IHooks, IBundlHook, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;

    error NotPoolManager();
    error NotInitialized();
    error AlreadyInitialized();
    error InvalidConfig();
    error InvalidWeights();
    error PoolNotRegistered();
    error ZeroUnits();
    error InsufficientBacking();
    error HookNotImplemented();
    error DirectLiquidityNotAllowed();
    error TooLittleReceived();
    error TooMuchRequested();
    error MissingUserAddress();

    IPoolManager public immutable poolManager;
    BundlToken   public indexToken;

    address[] public underlyingTokens;
    uint256[] public amountsPerUnit;
    uint256[] public underlyingWeightsBps;
    PoolKey[]  public underlyingPoolKeys;
    bool[]     public usdcIsCurrency0;
    uint8[]    public underlyingDecimals;

    PoolId public registeredPoolId;
    bool   public initialized;

    address public immutable usdc;
    uint8   public immutable usdcDecimals;

    uint256 internal constant BPS            = 10_000;
    uint256 internal constant WAD            = 1e18;
    uint160 internal constant MIN_SQRT_PRICE = 4295128739;
    uint160 internal constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }
    modifier whenInitialized() {
        if (!initialized) revert NotInitialized();
        _;
    }

    constructor(IPoolManager _poolManager, address _usdc, uint8 _usdcDecimals) {
        poolManager  = _poolManager;
        usdc         = _usdc;
        usdcDecimals = _usdcDecimals;

        Hooks.validateHookPermissions(
            IHooks(address(this)),
            Hooks.Permissions({
                beforeInitialize:               false,
                afterInitialize:                true,
                beforeAddLiquidity:             true,
                afterAddLiquidity:              false,
                beforeRemoveLiquidity:          false,
                afterRemoveLiquidity:           false,
                beforeSwap:                     true,
                afterSwap:                      true,
                beforeDonate:                   false,
                afterDonate:                    false,
                beforeSwapReturnDelta:          true,
                afterSwapReturnDelta:           false,
                afterAddLiquidityReturnDelta:   false,
                afterRemoveLiquidityReturnDelta: false
            })
        );
    }

    // ─────────────────────────── INITIALIZATION ───────────────────────────

    function initialize(
        address       _indexToken,
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        uint256[] calldata _weightsBps,
        PoolKey[]  calldata _poolKeys,
        bool[]    calldata _usdcIs0,
        uint8[]   calldata _underlyingDecimals
    ) external {
        if (initialized) revert AlreadyInitialized();
        uint256 n = _tokens.length;
        if (n == 0 || n != _amounts.length || n != _weightsBps.length
            || n != _poolKeys.length || n != _usdcIs0.length || n != _underlyingDecimals.length)
            revert InvalidConfig();

        uint256 totalBps;
        for (uint256 i; i < n; i++) totalBps += _weightsBps[i];
        if (totalBps != BPS) revert InvalidWeights();

        indexToken = BundlToken(_indexToken);
        for (uint256 i; i < n; i++) {
            underlyingTokens.push(_tokens[i]);
            amountsPerUnit.push(_amounts[i]);
            underlyingWeightsBps.push(_weightsBps[i]);
            underlyingPoolKeys.push(_poolKeys[i]);
            usdcIsCurrency0.push(_usdcIs0[i]);
            underlyingDecimals.push(_underlyingDecimals[i]);
        }
        initialized = true;
    }

    // ─────────────────────────── HOOK CALLBACKS ───────────────────────────

    function afterInitialize(address, PoolKey calldata key, uint160, int24)
        external override onlyPoolManager returns (bytes4)
    {
        registeredPoolId = key.toId();
        return IHooks.afterInitialize.selector;
    }

    function beforeAddLiquidity(
        address sender, PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata, bytes calldata
    ) external view override onlyPoolManager returns (bytes4) {
        if (sender != address(this)) revert DirectLiquidityNotAllowed();
        return IHooks.beforeAddLiquidity.selector;
    }

    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override onlyPoolManager whenInitialized returns (bytes4, BeforeSwapDelta, uint24) {
        if (PoolId.unwrap(key.toId()) != PoolId.unwrap(registeredPoolId)) revert PoolNotRegistered();

        bool indexIsCurrency0 = Currency.unwrap(key.currency0) == address(indexToken);
        bool isBuy = indexIsCurrency0 ? !params.zeroForOne : params.zeroForOne;

        uint256 absAmount = params.amountSpecified < 0
            ? uint256(-params.amountSpecified)
            : uint256(params.amountSpecified);

        return isBuy
            ? _handleBuy(params, absAmount, hookData)
            : _handleSell(params, absAmount, hookData);
    }

    function afterSwap(
        address, PoolKey calldata, IPoolManager.SwapParams calldata,
        BalanceDelta, bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        return (IHooks.afterSwap.selector, 0);
    }

    // ─────────────────────────── PUBLIC ───────────────────────────

    function redeem(uint256 indexAmount) external override nonReentrant whenInitialized {
        if (indexAmount == 0) revert ZeroUnits();
        indexToken.burn(msg.sender, indexAmount);
        uint256 n = underlyingTokens.length;
        uint256[] memory amounts = new uint256[](n);
        for (uint256 i; i < n; i++) {
            amounts[i] = FullMath.mulDiv(indexAmount, amountsPerUnit[i], WAD);
            if (IERC20(underlyingTokens[i]).balanceOf(address(this)) < amounts[i]) revert InsufficientBacking();
            IERC20(underlyingTokens[i]).safeTransfer(msg.sender, amounts[i]);
        }
        emit Redeemed(msg.sender, indexAmount, amounts);
    }

    // ─────────────────────────── VIEWS ───────────────────────────

    function getUnderlyingTokens()    external view override returns (address[] memory) { return underlyingTokens; }
    function getAmountsPerUnit()       external view override returns (uint256[] memory) { return amountsPerUnit; }
    function getUnderlyingWeightsBps() external view          returns (uint256[] memory) { return underlyingWeightsBps; }
    function getUnderlyingPoolKeys()   external view override returns (PoolKey[] memory) { return underlyingPoolKeys; }
    function getUsdcIs0()              external view          returns (bool[]    memory) { return usdcIsCurrency0; }

    function getTotalBacking() external view override returns (uint256[] memory balances) {
        uint256 n = underlyingTokens.length;
        balances = new uint256[](n);
        for (uint256 i; i < n; i++) balances[i] = IERC20(underlyingTokens[i]).balanceOf(address(this));
    }

    function getNavPerUnit() external view returns (uint256 nav) {
        for (uint256 i; i < underlyingTokens.length; i++) {
            (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(underlyingPoolKeys[i].toId());
            nav += _sqrtPriceToUsdcValue(sqrtPriceX96, usdcIsCurrency0[i], amountsPerUnit[i]);
        }
    }

    function getSpotPrice(uint256 idx) external view returns (uint256) {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(underlyingPoolKeys[idx].toId());
        return _sqrtPriceToUsdcValue(sqrtPriceX96, usdcIsCurrency0[idx], 10 ** underlyingDecimals[idx]);
    }

    function getSpotPrices() external view returns (uint256[] memory prices) {
        uint256 n = underlyingTokens.length;
        prices = new uint256[](n);
        for (uint256 i; i < n; i++) {
            (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(underlyingPoolKeys[i].toId());
            prices[i] = _sqrtPriceToUsdcValue(sqrtPriceX96, usdcIsCurrency0[i], 10 ** underlyingDecimals[i]);
        }
    }

    function getPoolStates()
        external view
        returns (uint160[] memory sqrtPrices, int24[] memory ticks, uint128[] memory liquidities)
    {
        uint256 n = underlyingTokens.length;
        sqrtPrices  = new uint160[](n);
        ticks       = new int24[](n);
        liquidities = new uint128[](n);
        for (uint256 i; i < n; i++) {
            (sqrtPrices[i], ticks[i],,) = poolManager.getSlot0(underlyingPoolKeys[i].toId());
            liquidities[i] = poolManager.getLiquidity(underlyingPoolKeys[i].toId());
        }
    }

    // ─────────────────────────── BUY HANDLER ───────────────────────────

    /// Exact-in buy: amountSpecified = -usdcIn
    ///   specifiedDelta   = +usdcIn   → hook takes USDC from PM; PM settles it from user
    ///   unspecifiedDelta = -indexOut → hook gives IndexToken to PM; PM delivers to user
    ///   amountToSwap = -usdcIn + usdcIn = 0
    function _handleBuy(
        IPoolManager.SwapParams calldata params,
        uint256 absAmount,
        bytes calldata hookData
    ) internal returns (bytes4, BeforeSwapDelta, uint24) {
        uint256 minOutput = hookData.length >= 32 ? abi.decode(hookData, (uint256)) : 0;
        bool    isExactIn = params.amountSpecified < 0;

        uint256 usdcAmount;
        uint256 indexToMint;

        if (isExactIn) {
            usdcAmount = absAmount;
            uint256 spent;
            (indexToMint, spent) = _buyUnderlyingWithUsdc(usdcAmount);
            usdcAmount = spent;
        } else {
            indexToMint = absAmount;
            if (indexToMint == 0) revert ZeroUnits();
            usdcAmount = _buyUnderlyingForIndexAmount(indexToMint);
            if (minOutput > 0 && usdcAmount > minOutput) revert TooMuchRequested();
        }

        if (indexToMint == 0) revert ZeroUnits();
        if (isExactIn && minOutput > 0 && indexToMint < minOutput) revert TooLittleReceived();

        // Deposit minted IndexToken into PM so it can deliver it to the user
        indexToken.mint(address(this), indexToMint);
        poolManager.sync(Currency.wrap(address(indexToken)));
        IERC20(address(indexToken)).transfer(address(poolManager), indexToMint);
        poolManager.settle();

        emit Minted(msg.sender, indexToMint, usdcAmount);

        return (
            IHooks.beforeSwap.selector,
            toBeforeSwapDelta(
                isExactIn ?  int128(uint128(usdcAmount))  : -int128(uint128(usdcAmount)),
                isExactIn ? -int128(uint128(indexToMint)) :  int128(uint128(indexToMint))
            ),
            0
        );
    }

    // ─────────────────────────── SELL HANDLER ───────────────────────────

    /// Exact-in sell: amountSpecified = -indexIn
    ///   hookData MUST be abi.encode(address user). User must have approved this hook.
    ///
    ///   Steps:
    ///     1. transferFrom(user → hook)
    ///     2. sync(IndexToken) + transfer(hook→PM) + settle()  → deposit into PM
    ///     3. take(IndexToken, hook, indexIn)                   → hook gets IndexToken back
    ///     4. burn(indexIn)
    ///     5. sell underlyings → USDC re-deposited into PM
    ///
    ///   specifiedDelta   = +indexIn    → hook takes IndexToken from PM
    ///                                     amountToSwap = -indexIn + indexIn = 0
    ///   unspecifiedDelta = -usdcOut    → hook gives USDC to PM; PM delivers to user
    function _handleSell(
        IPoolManager.SwapParams calldata params,
        uint256 absAmount,
        bytes calldata hookData
    ) internal returns (bytes4, BeforeSwapDelta, uint24) {
        if (hookData.length < 32) revert MissingUserAddress();
        address user      = abi.decode(hookData, (address));
        bool    isExactIn = params.amountSpecified < 0;

        uint256 indexToBurn;
        uint256 usdcReceived;

        if (isExactIn) {
            indexToBurn = absAmount;
            if (indexToBurn == 0) revert ZeroUnits();
        } else {
            usdcReceived = absAmount;
            indexToBurn  = _estimateIndexForUsdc(usdcReceived);
            if (indexToBurn == 0) revert ZeroUnits();
        }

        // 1. Pull IndexToken from user
        IERC20(address(indexToken)).safeTransferFrom(user, address(this), indexToBurn);

        // 2. Deposit IndexToken into PM (so the specifiedDelta accounting balances)
        poolManager.sync(Currency.wrap(address(indexToken)));
        IERC20(address(indexToken)).transfer(address(poolManager), indexToBurn);
        poolManager.settle();

        // 3. Take IndexToken back from PM into hook
        poolManager.take(Currency.wrap(address(indexToken)), address(this), indexToBurn);

        // 4. Burn
        indexToken.burn(address(this), indexToBurn);

        // 5. Sell underlyings → USDC ends up re-deposited in PM
        uint256 actualUsdc = _sellUnderlyingForUsdc(indexToBurn);

        if (isExactIn) {
            usdcReceived = actualUsdc;
        } else {
            if (actualUsdc < usdcReceived) revert TooLittleReceived();
            usdcReceived = actualUsdc;
        }

        emit Sold(user, indexToBurn, usdcReceived);

        return (
            IHooks.beforeSwap.selector,
            toBeforeSwapDelta(
                // specifiedDelta = +indexToBurn: hook takes IndexToken from PM
                // this makes amountToSwap = -indexToBurn + indexToBurn = 0
                int128(uint128(indexToBurn)),
                // unspecifiedDelta = -usdcReceived: hook gives USDC to PM → PM delivers to user
                -int128(uint128(usdcReceived))
            ),
            0
        );
    }

    // ─────────────────────────── UNDERLYING HELPERS ───────────────────────────

    function _buyUnderlyingWithUsdc(uint256 totalUsdc)
        internal returns (uint256 indexToMint, uint256 actualUsdcSpent)
    {
        uint256 n = underlyingTokens.length;
        uint256[] memory received = new uint256[](n);
        for (uint256 i; i < n; i++) {
            uint256 usdcForToken = totalUsdc * underlyingWeightsBps[i] / BPS;
            received[i]      = _swapExactUsdcForUnderlying(i, usdcForToken);
            actualUsdcSpent += usdcForToken;
        }
        indexToMint = type(uint256).max;
        for (uint256 i; i < n; i++) {
            uint256 units = FullMath.mulDiv(received[i], WAD, amountsPerUnit[i]);
            if (units < indexToMint) indexToMint = units;
        }
        if (indexToMint == 0) revert ZeroUnits();
    }

    function _buyUnderlyingForIndexAmount(uint256 indexAmount)
        internal returns (uint256 totalUsdcSpent)
    {
        for (uint256 i; i < underlyingTokens.length; i++) {
            uint256 needed  = FullMath.mulDiv(indexAmount, amountsPerUnit[i], WAD);
            totalUsdcSpent += _swapUsdcForExactUnderlying(i, needed);
        }
    }

    function _sellUnderlyingForUsdc(uint256 indexAmount)
        internal returns (uint256 usdcReceived)
    {
        for (uint256 i; i < underlyingTokens.length; i++) {
            uint256 underlyingAmt = FullMath.mulDiv(indexAmount, amountsPerUnit[i], WAD);
            if (IERC20(underlyingTokens[i]).balanceOf(address(this)) < underlyingAmt)
                revert InsufficientBacking();
            usdcReceived += _swapExactUnderlyingForUsdc(i, underlyingAmt);
        }
    }

    function _estimateIndexForUsdc(uint256 targetUsdc)
        internal view returns (uint256 indexAmount)
    {
        uint256 nav;
        for (uint256 i; i < underlyingTokens.length; i++) {
            (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(underlyingPoolKeys[i].toId());
            nav += _sqrtPriceToUsdcValue(sqrtPriceX96, usdcIsCurrency0[i], amountsPerUnit[i]);
        }
        if (nav == 0) return WAD;
        indexAmount = FullMath.mulDiv(targetUsdc, WAD, nav);
        if (indexAmount == 0) indexAmount = 1;
    }

    // ─────────────────────────── SWAP PRIMITIVES ───────────────────────────

    function _swapExactUsdcForUnderlying(uint256 idx, uint256 usdcAmount)
        internal returns (uint256 underlyingReceived)
    {
        PoolKey memory key       = underlyingPoolKeys[idx];
        bool          z4o        = usdcIsCurrency0[idx];
        BalanceDelta  delta      = poolManager.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne:        z4o,
                amountSpecified:   -int256(usdcAmount),
                sqrtPriceLimitX96: z4o ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1
            }),
            ""
        );
        int128 out = z4o ? delta.amount1() : delta.amount0();
        underlyingReceived = uint256(uint128(out > 0 ? out : -out));
        poolManager.take(Currency.wrap(underlyingTokens[idx]), address(this), underlyingReceived);
    }

    function _swapUsdcForExactUnderlying(uint256 idx, uint256 underlyingAmount)
        internal returns (uint256 usdcSpent)
    {
        PoolKey memory key  = underlyingPoolKeys[idx];
        bool          z4o   = usdcIsCurrency0[idx];
        BalanceDelta  delta = poolManager.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne:        z4o,
                amountSpecified:   int256(underlyingAmount),
                sqrtPriceLimitX96: z4o ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1
            }),
            ""
        );
        int128 inp = z4o ? delta.amount0() : delta.amount1();
        usdcSpent  = uint256(uint128(inp < 0 ? -inp : inp));
        poolManager.take(Currency.wrap(underlyingTokens[idx]), address(this), underlyingAmount);
    }

    /// @dev Underlying → USDC.
    ///   1. swap(underlying → USDC)           PM owes hook USDC; hook owes PM underlying
    ///   2. take(USDC → hook)                 hook receives USDC
    ///   3. sync+transfer(underlying)+settle  pays underlying debt
    ///   4. sync+transfer(USDC)+settle        re-deposits USDC into PM
    ///      PM now holds real USDC, which the outer -usdcReceived delta credits to the user
    function _swapExactUnderlyingForUsdc(uint256 idx, uint256 underlyingAmount)
        internal returns (uint256 usdcReceived)
    {
        PoolKey memory key  = underlyingPoolKeys[idx];
        bool          z4o   = !usdcIsCurrency0[idx];

        BalanceDelta delta = poolManager.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne:        z4o,
                amountSpecified:   -int256(underlyingAmount),
                sqrtPriceLimitX96: z4o ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1
            }),
            ""
        );

        int128 out = z4o ? delta.amount1() : delta.amount0();
        usdcReceived = uint256(uint128(out > 0 ? out : -out));

        poolManager.take(Currency.wrap(usdc), address(this), usdcReceived);

        poolManager.sync(Currency.wrap(underlyingTokens[idx]));
        IERC20(underlyingTokens[idx]).safeTransfer(address(poolManager), underlyingAmount);
        poolManager.settle();

        poolManager.sync(Currency.wrap(usdc));
        IERC20(usdc).safeTransfer(address(poolManager), usdcReceived);
        poolManager.settle();
    }

    // ─────────────────────────── PRICE PRIMITIVE ───────────────────────────

    function _sqrtPriceToUsdcValue(uint160 sqrtPriceX96, bool usdcIs0, uint256 tokenAmount)
        internal pure returns (uint256 usdcValue)
    {
        uint256 sq = uint256(sqrtPriceX96);
        if (usdcIs0) {
            usdcValue = FullMath.mulDiv(FullMath.mulDiv(tokenAmount, 1 << 96, sq), 1 << 96, sq);
        } else {
            usdcValue = FullMath.mulDiv(FullMath.mulDiv(tokenAmount, sq, 1 << 96), sq, 1 << 96);
        }
    }

    // ─────────────────────────── UNIMPLEMENTED HOOKS ───────────────────────────

    function beforeInitialize(address, PoolKey calldata, uint160)
        external pure override returns (bytes4) { revert HookNotImplemented(); }
    function afterAddLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata)
        external pure override returns (bytes4, BalanceDelta) { revert HookNotImplemented(); }
    function beforeRemoveLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        external pure override returns (bytes4) { revert HookNotImplemented(); }
    function afterRemoveLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata)
        external pure override returns (bytes4, BalanceDelta) { revert HookNotImplemented(); }
    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external pure override returns (bytes4) { revert HookNotImplemented(); }
    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external pure override returns (bytes4) { revert HookNotImplemented(); }
}
