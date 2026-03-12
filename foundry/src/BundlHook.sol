// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
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
/// @notice Uniswap v4 NoOp hook that acts as a NAV-priced market maker for index tokens.
///         Intercepts swaps in the IndexToken/USDC pool, acquires underlying assets via
///         other v4 pools, and mints/burns the index token at NAV price.
/// @dev Requires beforeSwap + beforeSwapReturnDelta permissions (NoOp pattern).
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

    /// @notice Underlying tokens in the index basket
    address[] public underlyingTokens;

    /// @notice Amount of each underlying token per 1 unit of index (scaled to token decimals)
    uint256[] public amountsPerUnit;

    /// @notice Weight of each underlying token in basis points (sum must equal 10000)
    uint256[] public underlyingWeightsBps;

    /// @notice PoolKeys for USDC/<underlying> pools used to swap
    PoolKey[] public underlyingPoolKeys;

    /// @notice Whether USDC is currency0 in each underlying pool
    bool[] public usdcIsCurrency0;

    /// @notice Decimals for each underlying token
    uint8[] public underlyingDecimals;

    /// @notice The registered IndexToken/USDC pool
    PoolId public registeredPoolId;
    bool public initialized;

    /// @notice USDC token address
    address public immutable usdc;

    /// @notice USDC decimals (typically 6)
    uint8 public immutable usdcDecimals;

    uint256 internal constant BPS = 10000;
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
                afterSwap: false,
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

    // ═══════════════════════════════════════════════════════════════════════
    // PUBLIC FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function redeem(uint256 units) external override nonReentrant whenInitialized {
        if (units == 0) revert ZeroUnits();
        uint256 indexAmount = units * 1e18;
        indexToken.burn(msg.sender, indexAmount);

        uint256[] memory amounts = new uint256[](underlyingTokens.length);
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            amounts[i] = units * amountsPerUnit[i];
            if (IERC20(underlyingTokens[i]).balanceOf(address(this)) < amounts[i]) revert InsufficientBacking();
            IERC20(underlyingTokens[i]).safeTransfer(msg.sender, amounts[i]);
        }
        emit Redeemed(msg.sender, units, amounts);
    }

    function sweepAndBurnIndex() external nonReentrant whenInitialized {
        uint256 indexTokenCurrencyId = uint256(uint160(address(indexToken)));
        uint256 claims = poolManager.balanceOf(address(this), indexTokenCurrencyId);
        if (claims == 0) return;
        poolManager.unlock(abi.encode(claims));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(poolManager), "Only PM");
        uint256 claims = abi.decode(data, (uint256));
        uint256 indexTokenCurrencyId = uint256(uint160(address(indexToken)));
        poolManager.burn(address(this), indexTokenCurrencyId, claims);
        poolManager.take(Currency.wrap(address(indexToken)), address(this), claims);
        indexToken.burn(address(this), claims);
        return "";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function getUnderlyingTokens() external view override returns (address[] memory) {
        return underlyingTokens;
    }

    function getAmountsPerUnit() external view override returns (uint256[] memory) {
        return amountsPerUnit;
    }

    function getUnderlyingWeightsBps() external view returns (uint256[] memory) {
        return underlyingWeightsBps;
    }

    function getUnderlyingPoolKeys() external view override returns (PoolKey[] memory) {
        return underlyingPoolKeys;
    }

    function getTotalBacking() external view override returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](underlyingTokens.length);
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            balances[i] = IERC20(underlyingTokens[i]).balanceOf(address(this));
        }
        return balances;
    }

    function getUsdcIs0() external view returns (bool[] memory) {
        return usdcIsCurrency0;
    }

    /// @notice Returns the current spot price (in USDC, scaled to usdcDecimals) for 1 full token
    ///         of the underlying at index `tokenIndex`.
    /// @dev    This is a pure read — no state changes. Safe to call from any frontend or contract.
    ///         Works for any token/USDC decimal combination.
    function getSpotPrice(uint256 tokenIndex) external view returns (uint256 spotPriceUsdc) {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(underlyingPoolKeys[tokenIndex].toId());
        uint256 oneToken = 10 ** underlyingDecimals[tokenIndex];
        spotPriceUsdc = _sqrtPriceToUsdcValue(
            sqrtPriceX96,
            usdcIsCurrency0[tokenIndex],
            oneToken
        );
    }

    /// @notice Returns spot prices for all underlying tokens in one call.
    function getSpotPrices() external view returns (uint256[] memory spotPricesUsdc) {
        uint256 n = underlyingTokens.length;
        spotPricesUsdc = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(underlyingPoolKeys[i].toId());
            uint256 oneToken = 10 ** underlyingDecimals[i];
            spotPricesUsdc[i] = _sqrtPriceToUsdcValue(sqrtPriceX96, usdcIsCurrency0[i], oneToken);
        }
    }

    /// @notice Get sqrtPriceX96, tick, and liquidity for each underlying pool
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

    /// @notice NAV per index unit in USDC (scaled to usdcDecimals)
    function getNavPerUnit() external view returns (uint256 navPerUnit) {
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(underlyingPoolKeys[i].toId());
            navPerUnit += _sqrtPriceToUsdcValue(
                sqrtPriceX96,
                usdcIsCurrency0[i],
                amountsPerUnit[i]
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: BUY LOGIC
    // ═══════════════════════════════════════════════════════════════════════

    function _handleBuy(IPoolManager.SwapParams calldata params, uint256 absAmount, bytes calldata hookData)
        internal returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint256 minOutput = hookData.length > 0 ? abi.decode(hookData, (uint256)) : 0;
        bool isExactInput = params.amountSpecified < 0;

        uint256 usdcAmount;
        uint256 units;

        if (isExactInput) {
            usdcAmount = absAmount;
            uint256 actualUsdcSpent;
            (units, actualUsdcSpent) = _buyUnderlyingWithUsdc(usdcAmount);
            usdcAmount = actualUsdcSpent;
        } else {
            units = absAmount / 1e18;
            if (units == 0) revert ZeroUnits();
            usdcAmount = _buyUnderlyingForUnits(units);
            if (minOutput > 0 && usdcAmount > minOutput) revert TooMuchRequested();
        }

        uint256 indexTokensToMint = units * 1e18;
        if (isExactInput && minOutput > 0 && indexTokensToMint < minOutput) revert TooLittleReceived();

        indexToken.mint(address(this), indexTokensToMint);
        poolManager.sync(Currency.wrap(address(indexToken)));
        IERC20(address(indexToken)).transfer(address(poolManager), indexTokensToMint);
        poolManager.settle();

        emit Minted(msg.sender, units, usdcAmount);

        int128 deltaUnspecified = isExactInput
            ? -int128(uint128(indexTokensToMint))
            : int128(uint128(usdcAmount));

        return (IHooks.beforeSwap.selector, toBeforeSwapDelta(int128(-params.amountSpecified), deltaUnspecified), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: SELL LOGIC
    // ═══════════════════════════════════════════════════════════════════════

    function _handleSell(IPoolManager.SwapParams calldata params, uint256 absAmount, bytes calldata hookData)
        internal returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint256 minOutput = hookData.length > 0 ? abi.decode(hookData, (uint256)) : 0;
        bool isExactInput = params.amountSpecified < 0;

        uint256 units;
        uint256 usdcReceived;

        if (isExactInput) {
            units = absAmount / 1e18;
            if (units == 0) revert ZeroUnits();
        } else {
            usdcReceived = absAmount;
            units = _estimateUnitsForUsdc(usdcReceived);
            if (units == 0) revert ZeroUnits();
        }

        uint256 indexTokensToBurn = units * 1e18;
        if (!isExactInput && minOutput > 0 && indexTokensToBurn > minOutput) revert TooMuchRequested();

        uint256 indexTokenCurrencyId = uint256(uint160(address(indexToken)));
        poolManager.mint(address(this), indexTokenCurrencyId, indexTokensToBurn);

        uint256 actualUsdcReceived = _sellUnderlyingForUsdc(units);

        if (isExactInput) {
            usdcReceived = actualUsdcReceived;
            if (minOutput > 0 && usdcReceived < minOutput) revert TooLittleReceived();
        } else {
            if (actualUsdcReceived < usdcReceived) revert TooLittleReceived();
        }

        emit Sold(msg.sender, units, usdcReceived);

        int128 deltaUnspecified = isExactInput
            ? -int128(uint128(usdcReceived))
            : int128(uint128(indexTokensToBurn));

        return (IHooks.beforeSwap.selector, toBeforeSwapDelta(int128(-params.amountSpecified), deltaUnspecified), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: UNDERLYING SWAP HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    function _buyUnderlyingWithUsdc(uint256 totalUsdc)
        internal returns (uint256 units, uint256 actualUsdcSpent)
    {
        uint256 numTokens = underlyingTokens.length;
        uint256[] memory underlyingReceived = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            uint256 usdcForToken = totalUsdc * underlyingWeightsBps[i] / BPS;
            underlyingReceived[i] = _swapExactUsdcForUnderlying(i, usdcForToken);
            actualUsdcSpent += usdcForToken;
        }

        units = type(uint256).max;
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 unitsFromThis = underlyingReceived[i] / amountsPerUnit[i];
            if (unitsFromThis < units) units = unitsFromThis;
        }
        if (units == 0) revert ZeroUnits();
    }

    function _buyUnderlyingForUnits(uint256 units) internal returns (uint256 totalUsdcSpent) {
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            totalUsdcSpent += _swapUsdcForExactUnderlying(i, units * amountsPerUnit[i]);
        }
    }

    function _sellUnderlyingForUsdc(uint256 units) internal returns (uint256 usdcReceived) {
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            uint256 underlyingAmount = units * amountsPerUnit[i];
            if (IERC20(underlyingTokens[i]).balanceOf(address(this)) < underlyingAmount) revert InsufficientBacking();
            usdcReceived += _swapExactUnderlyingForUsdc(i, underlyingAmount);
        }
    }

    function _estimateUnitsForUsdc(uint256 targetUsdc) internal view returns (uint256 units) {
        uint256 navPerUnit = 0;
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(underlyingPoolKeys[i].toId());
            navPerUnit += _sqrtPriceToUsdcValue(sqrtPriceX96, usdcIsCurrency0[i], amountsPerUnit[i]);
        }
        if (navPerUnit == 0) return 1;
        units = (targetUsdc + navPerUnit - 1) / navPerUnit;
        if (units == 0) units = 1;
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

        int128 outputAmount = zeroForOne ? delta.amount1() : delta.amount0();
        underlyingReceived = uint256(uint128(outputAmount > 0 ? outputAmount : -outputAmount));
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

        int128 inputAmount = zeroForOne ? delta.amount0() : delta.amount1();
        usdcSpent = uint256(uint128(inputAmount < 0 ? -inputAmount : inputAmount));
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

        int128 outputAmount = zeroForOne ? delta.amount1() : delta.amount0();
        usdcReceived = uint256(uint128(outputAmount > 0 ? outputAmount : -outputAmount));

        poolManager.sync(Currency.wrap(underlyingTokens[tokenIndex]));
        IERC20(underlyingTokens[tokenIndex]).safeTransfer(address(poolManager), underlyingAmount);
        poolManager.settle();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: PRICE PRIMITIVE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Core price primitive. Converts any `tokenAmount` (in token wei) to its USDC
    ///         equivalent (in usdcWei) using the pool's current sqrtPriceX96.
    ///
    /// @dev    sqrtPriceX96 = sqrt(c1_wei / c0_wei) * 2^96
    ///
    ///         usdcIs0 = true  (c0=USDC, c1=token):
    ///           ratio = (sqrtP/2^96)^2 = tokenWei/usdcWei
    ///           usdcValue = tokenAmount * (2^96)^2 / sqrtP^2
    ///           Units: tokenWei * (usdcWei/tokenWei) = usdcWei  ✔️  no extra decimal adjustment needed.
    ///
    ///         usdcIs0 = false (c0=token, c1=USDC):
    ///           ratio = (sqrtP/2^96)^2 = usdcWei/tokenWei
    ///           usdcValue = tokenAmount * sqrtP^2 / (2^96)^2
    ///           Units: tokenWei * (usdcWei/tokenWei) = usdcWei  ✔️  no extra decimal adjustment needed.
    ///
    ///         In both cases the wei units cancel perfectly regardless of tokenDecimals or
    ///         usdcDecimals, so NO additional decimal scaling is applied here.
    ///         This makes the function safe for any (tokenDecimals, usdcDecimals) pair.
    function _sqrtPriceToUsdcValue(
        uint160 sqrtPriceX96,
        bool usdcIs0,
        uint256 tokenAmount
    ) internal pure returns (uint256 usdcValue) {
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        if (usdcIs0) {
            // usdcValue = tokenAmount / (sqrtP/2^96)^2 = tokenAmount * 2^192 / sqrtP^2
            uint256 intermediate = FullMath.mulDiv(tokenAmount, 1 << 96, sqrtPrice);
            usdcValue = FullMath.mulDiv(intermediate, 1 << 96, sqrtPrice);
        } else {
            // usdcValue = tokenAmount * (sqrtP/2^96)^2 = tokenAmount * sqrtP^2 / 2^192
            uint256 intermediate = FullMath.mulDiv(tokenAmount, sqrtPrice, 1 << 96);
            usdcValue = FullMath.mulDiv(intermediate, sqrtPrice, 1 << 96);
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
    function afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external pure override returns (bytes4, int128) { revert HookNotImplemented(); }
    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external pure override returns (bytes4) { revert HookNotImplemented(); }
    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external pure override returns (bytes4) { revert HookNotImplemented(); }
}
