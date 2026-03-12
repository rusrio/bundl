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
/// @notice Uniswap v4 hook that acts as a NAV-priced market maker for index tokens.
///         Intercepts swaps in the IndexToken/USDC pool, acquires underlying assets via
///         other v4 pools, and mints/burns the index token at NAV price.
///
/// @dev    Sell burn pattern:
///           beforeSwap  → sells underlying, records _pendingBurn, returns delta
///           afterSwap   → takes index tokens from PM (now settled by router), burns them
///         This is atomic within one tx and correctly reduces totalSupply.
///
/// @dev    Units convention: all "index amounts" are in 1e18 scale (ERC-20 wei).
contract BundlHook is IHooks, IBundlHook, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

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

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    IPoolManager public immutable poolManager;
    BundlToken public indexToken;

    address[] public underlyingTokens;
    /// @dev Amount of each underlying per 1e18 index tokens (amountsPerUnit[i] * indexWei / 1e18 = underlyingWei)
    uint256[] public amountsPerUnit;
    uint256[] public underlyingWeightsBps;
    PoolKey[] public underlyingPoolKeys;
    bool[] public usdcIsCurrency0;
    uint8[] public underlyingDecimals;

    PoolId public registeredPoolId;
    bool public initialized;

    address public immutable usdc;
    uint8 public immutable usdcDecimals;

    /// @dev Transient: index tokens to burn in the upcoming afterSwap. Set in beforeSwap, cleared in afterSwap.
    uint256 private _pendingBurn;

    uint256 internal constant BPS = 10_000;
    uint256 internal constant WAD = 1e18;
    uint160 internal constant MIN_SQRT_PRICE = 4295128739;
    uint160 internal constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    modifier whenInitialized() {
        if (!initialized) revert NotInitialized();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(IPoolManager _poolManager, address _usdc, uint8 _usdcDecimals) {
        poolManager = _poolManager;
        usdc = _usdc;
        usdcDecimals = _usdcDecimals;

        Hooks.validateHookPermissions(
            IHooks(address(this)),
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: true,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            })
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════

    function initialize(
        address _indexToken,
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        uint256[] calldata _weightsBps,
        PoolKey[] calldata _poolKeys,
        bool[] calldata _usdcIs0,
        uint8[] calldata _underlyingDecimals
    ) external {
        if (initialized) revert AlreadyInitialized();
        if (
            _tokens.length == 0
                || _tokens.length != _amounts.length
                || _tokens.length != _weightsBps.length
                || _tokens.length != _poolKeys.length
                || _tokens.length != _usdcIs0.length
                || _tokens.length != _underlyingDecimals.length
        ) revert InvalidConfig();

        uint256 totalBps = 0;
        for (uint256 i = 0; i < _weightsBps.length; i++) totalBps += _weightsBps[i];
        if (totalBps != BPS) revert InvalidWeights();

        indexToken = BundlToken(_indexToken);
        for (uint256 i = 0; i < _tokens.length; i++) {
            underlyingTokens.push(_tokens[i]);
            amountsPerUnit.push(_amounts[i]);
            underlyingWeightsBps.push(_weightsBps[i]);
            underlyingPoolKeys.push(_poolKeys[i]);
            usdcIsCurrency0.push(_usdcIs0[i]);
            underlyingDecimals.push(_underlyingDecimals[i]);
        }
        initialized = true;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HOOK CALLBACKS
    // ═══════════════════════════════════════════════════════════════════════

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

        bool indexTokenIsCurrency0 = Currency.unwrap(key.currency0) == address(indexToken);
        bool isBuy = indexTokenIsCurrency0 ? !params.zeroForOne : params.zeroForOne;

        uint256 absAmount = params.amountSpecified < 0
            ? uint256(-params.amountSpecified)
            : uint256(params.amountSpecified);

        return isBuy
            ? _handleBuy(params, absAmount, hookData)
            : _handleSell(params, absAmount, hookData);
    }

    /// @notice Burns the index tokens that the router deposited into the PM during a sell.
    /// @dev    _pendingBurn is set in _handleSell and cleared here. No-op for buys.
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        if (PoolId.unwrap(key.toId()) != PoolId.unwrap(registeredPoolId)) {
            return (IHooks.afterSwap.selector, 0);
        }

        uint256 toBurn = _pendingBurn;
        if (toBurn > 0) {
            _pendingBurn = 0;
            // Router has now settled: index tokens are in the PM. Take and burn them.
            poolManager.take(Currency.wrap(address(indexToken)), address(this), toBurn);
            indexToken.burn(address(this), toBurn);
        }

        return (IHooks.afterSwap.selector, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PUBLIC FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Redeem index tokens for proportional underlying assets (bypass the pool).
    /// @param  indexAmount  ERC-20 amount to redeem (1e18 = 1 full unit).
    function redeem(uint256 indexAmount) external override nonReentrant whenInitialized {
        if (indexAmount == 0) revert ZeroUnits();
        indexToken.burn(msg.sender, indexAmount);

        uint256[] memory amounts = new uint256[](underlyingTokens.length);
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            amounts[i] = FullMath.mulDiv(indexAmount, amountsPerUnit[i], WAD);
            if (IERC20(underlyingTokens[i]).balanceOf(address(this)) < amounts[i]) revert InsufficientBacking();
            IERC20(underlyingTokens[i]).safeTransfer(msg.sender, amounts[i]);
        }
        emit Redeemed(msg.sender, indexAmount, amounts);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function getUnderlyingTokens() external view override returns (address[] memory) { return underlyingTokens; }
    function getAmountsPerUnit() external view override returns (uint256[] memory) { return amountsPerUnit; }
    function getUnderlyingWeightsBps() external view returns (uint256[] memory) { return underlyingWeightsBps; }
    function getUnderlyingPoolKeys() external view override returns (PoolKey[] memory) { return underlyingPoolKeys; }
    function getUsdcIs0() external view returns (bool[] memory) { return usdcIsCurrency0; }

    function getTotalBacking() external view override returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](underlyingTokens.length);
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            balances[i] = IERC20(underlyingTokens[i]).balanceOf(address(this));
        }
        return balances;
    }

    function getSpotPrice(uint256 tokenIndex) external view returns (uint256) {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(underlyingPoolKeys[tokenIndex].toId());
        return _sqrtPriceToUsdcValue(sqrtPriceX96, usdcIsCurrency0[tokenIndex], 10 ** underlyingDecimals[tokenIndex]);
    }

    function getSpotPrices() external view returns (uint256[] memory prices) {
        uint256 n = underlyingTokens.length;
        prices = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
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
        for (uint256 i = 0; i < n; i++) {
            (sqrtPrices[i], ticks[i],,) = poolManager.getSlot0(underlyingPoolKeys[i].toId());
            liquidities[i] = poolManager.getLiquidity(underlyingPoolKeys[i].toId());
        }
    }

    function getNavPerUnit() external view returns (uint256 nav) {
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(underlyingPoolKeys[i].toId());
            nav += _sqrtPriceToUsdcValue(sqrtPriceX96, usdcIsCurrency0[i], amountsPerUnit[i]);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: BUY
    // ═══════════════════════════════════════════════════════════════════════

    function _handleBuy(IPoolManager.SwapParams calldata params, uint256 absAmount, bytes calldata hookData)
        internal returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint256 minOutput = hookData.length > 0 ? abi.decode(hookData, (uint256)) : 0;
        bool isExactInput = params.amountSpecified < 0;

        uint256 usdcAmount;
        uint256 indexTokensToMint;

        if (isExactInput) {
            usdcAmount = absAmount;
            uint256 actualUsdcSpent;
            (indexTokensToMint, actualUsdcSpent) = _buyUnderlyingWithUsdc(usdcAmount);
            usdcAmount = actualUsdcSpent;
        } else {
            indexTokensToMint = absAmount;
            if (indexTokensToMint == 0) revert ZeroUnits();
            usdcAmount = _buyUnderlyingForIndexAmount(indexTokensToMint);
            if (minOutput > 0 && usdcAmount > minOutput) revert TooMuchRequested();
        }

        if (indexTokensToMint == 0) revert ZeroUnits();
        if (isExactInput && minOutput > 0 && indexTokensToMint < minOutput) revert TooLittleReceived();

        indexToken.mint(address(this), indexTokensToMint);
        poolManager.sync(Currency.wrap(address(indexToken)));
        IERC20(address(indexToken)).transfer(address(poolManager), indexTokensToMint);
        poolManager.settle();

        emit Minted(msg.sender, indexTokensToMint, usdcAmount);

        int128 deltaUnspecified = isExactInput
            ? -int128(uint128(indexTokensToMint))
            :  int128(uint128(usdcAmount));

        return (IHooks.beforeSwap.selector, toBeforeSwapDelta(int128(-params.amountSpecified), deltaUnspecified), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: SELL
    // ═══════════════════════════════════════════════════════════════════════

    function _handleSell(IPoolManager.SwapParams calldata params, uint256 absAmount, bytes calldata hookData)
        internal returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint256 minOutput = hookData.length > 0 ? abi.decode(hookData, (uint256)) : 0;
        bool isExactInput = params.amountSpecified < 0;

        uint256 indexTokensToBurn;
        uint256 usdcReceived;

        if (isExactInput) {
            indexTokensToBurn = absAmount;
            if (indexTokensToBurn == 0) revert ZeroUnits();
        } else {
            usdcReceived = absAmount;
            indexTokensToBurn = _estimateIndexForUsdc(usdcReceived);
            if (indexTokensToBurn == 0) revert ZeroUnits();
            if (minOutput > 0 && indexTokensToBurn > minOutput) revert TooMuchRequested();
        }

        // Store for afterSwap — the router hasn't settled the user's index tokens yet.
        _pendingBurn = indexTokensToBurn;

        // Sell underlying proportional to indexTokensToBurn and deliver USDC to PM.
        uint256 actualUsdcReceived = _sellUnderlyingForUsdc(indexTokensToBurn);

        if (isExactInput) {
            usdcReceived = actualUsdcReceived;
            if (minOutput > 0 && usdcReceived < minOutput) revert TooLittleReceived();
        } else {
            if (actualUsdcReceived < usdcReceived) revert TooLittleReceived();
        }

        emit Sold(msg.sender, indexTokensToBurn, usdcReceived);

        int128 deltaUnspecified = isExactInput
            ? -int128(uint128(usdcReceived))
            :  int128(uint128(indexTokensToBurn));

        return (IHooks.beforeSwap.selector, toBeforeSwapDelta(int128(-params.amountSpecified), deltaUnspecified), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: UNDERLYING SWAP HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    function _buyUnderlyingWithUsdc(uint256 totalUsdc)
        internal returns (uint256 indexTokensToMint, uint256 actualUsdcSpent)
    {
        uint256 n = underlyingTokens.length;
        uint256[] memory received = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            uint256 usdcForToken = totalUsdc * underlyingWeightsBps[i] / BPS;
            received[i] = _swapExactUsdcForUnderlying(i, usdcForToken);
            actualUsdcSpent += usdcForToken;
        }
        indexTokensToMint = type(uint256).max;
        for (uint256 i = 0; i < n; i++) {
            uint256 fromThis = FullMath.mulDiv(received[i], WAD, amountsPerUnit[i]);
            if (fromThis < indexTokensToMint) indexTokensToMint = fromThis;
        }
        if (indexTokensToMint == 0) revert ZeroUnits();
    }

    function _buyUnderlyingForIndexAmount(uint256 indexAmount) internal returns (uint256 totalUsdcSpent) {
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            uint256 underlyingNeeded = FullMath.mulDiv(indexAmount, amountsPerUnit[i], WAD);
            totalUsdcSpent += _swapUsdcForExactUnderlying(i, underlyingNeeded);
        }
    }

    function _sellUnderlyingForUsdc(uint256 indexAmount) internal returns (uint256 usdcReceived) {
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            uint256 underlyingAmount = FullMath.mulDiv(indexAmount, amountsPerUnit[i], WAD);
            if (IERC20(underlyingTokens[i]).balanceOf(address(this)) < underlyingAmount) revert InsufficientBacking();
            usdcReceived += _swapExactUnderlyingForUsdc(i, underlyingAmount);
        }
    }

    function _estimateIndexForUsdc(uint256 targetUsdc) internal view returns (uint256 indexAmount) {
        uint256 nav = 0;
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(underlyingPoolKeys[i].toId());
            nav += _sqrtPriceToUsdcValue(sqrtPriceX96, usdcIsCurrency0[i], amountsPerUnit[i]);
        }
        if (nav == 0) return WAD;
        indexAmount = FullMath.mulDiv(targetUsdc, WAD, nav);
        if (indexAmount == 0) indexAmount = 1;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: ATOMIC SWAP EXECUTION
    // ═══════════════════════════════════════════════════════════════════════

    function _swapExactUsdcForUnderlying(uint256 tokenIndex, uint256 usdcAmount)
        internal returns (uint256 underlyingReceived)
    {
        PoolKey memory poolKey = underlyingPoolKeys[tokenIndex];
        bool zeroForOne = usdcIsCurrency0[tokenIndex];
        BalanceDelta delta = poolManager.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(usdcAmount),
                sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1
            }),
            ""
        );
        int128 out = zeroForOne ? delta.amount1() : delta.amount0();
        underlyingReceived = uint256(uint128(out > 0 ? out : -out));
        poolManager.take(Currency.wrap(underlyingTokens[tokenIndex]), address(this), underlyingReceived);
    }

    function _swapUsdcForExactUnderlying(uint256 tokenIndex, uint256 underlyingAmount)
        internal returns (uint256 usdcSpent)
    {
        PoolKey memory poolKey = underlyingPoolKeys[tokenIndex];
        bool zeroForOne = usdcIsCurrency0[tokenIndex];
        BalanceDelta delta = poolManager.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: int256(underlyingAmount),
                sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1
            }),
            ""
        );
        int128 inp = zeroForOne ? delta.amount0() : delta.amount1();
        usdcSpent = uint256(uint128(inp < 0 ? -inp : inp));
        poolManager.take(Currency.wrap(underlyingTokens[tokenIndex]), address(this), underlyingAmount);
    }

    function _swapExactUnderlyingForUsdc(uint256 tokenIndex, uint256 underlyingAmount)
        internal returns (uint256 usdcReceived)
    {
        PoolKey memory poolKey = underlyingPoolKeys[tokenIndex];
        bool zeroForOne = !usdcIsCurrency0[tokenIndex];
        BalanceDelta delta = poolManager.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(underlyingAmount),
                sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1
            }),
            ""
        );
        int128 out = zeroForOne ? delta.amount1() : delta.amount0();
        usdcReceived = uint256(uint128(out > 0 ? out : -out));
        poolManager.sync(Currency.wrap(underlyingTokens[tokenIndex]));
        IERC20(underlyingTokens[tokenIndex]).safeTransfer(address(poolManager), underlyingAmount);
        poolManager.settle();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: PRICE PRIMITIVE
    // ═══════════════════════════════════════════════════════════════════════

    function _sqrtPriceToUsdcValue(uint160 sqrtPriceX96, bool usdcIs0, uint256 tokenAmount)
        internal pure returns (uint256 usdcValue)
    {
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        if (usdcIs0) {
            uint256 i = FullMath.mulDiv(tokenAmount, 1 << 96, sqrtPrice);
            usdcValue = FullMath.mulDiv(i, 1 << 96, sqrtPrice);
        } else {
            uint256 i = FullMath.mulDiv(tokenAmount, sqrtPrice, 1 << 96);
            usdcValue = FullMath.mulDiv(i, sqrtPrice, 1 << 96);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // UNIMPLEMENTED HOOK CALLBACKS
    // ═══════════════════════════════════════════════════════════════════════

    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }
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
