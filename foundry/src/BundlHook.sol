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

    /// @notice PoolKeys for USDC/<underlying> pools used to swap
    PoolKey[] public underlyingPoolKeys;

    /// @notice Whether USDC is currency0 in each underlying pool
    bool[] public usdcIsCurrency0;

    /// @notice Decimals for each underlying token (e.g. 18 for WETH, 8 for WBTC)
    uint8[] public underlyingDecimals;

    /// @notice The registered IndexToken/USDC pool
    PoolId public registeredPoolId;
    bool public initialized;

    /// @notice USDC token address
    address public immutable usdc;

    /// @notice USDC decimals (typically 6)
    uint8 public immutable usdcDecimals;

    /// @notice Sqrt price constants for swap limits
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

        // Validate hook address has the correct permission flags
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
    // INITIALIZATION (called by factory)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Initialize the hook with the index token and underlying configuration
    function initialize(
        address _indexToken,
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        PoolKey[] calldata _poolKeys,
        bool[] calldata _usdcIs0,
        uint8[] calldata _underlyingDecimals
    ) external {
        if (initialized) revert AlreadyInitialized();
        if (
            _tokens.length == 0 || _tokens.length != _amounts.length || _tokens.length != _poolKeys.length
                || _tokens.length != _usdcIs0.length || _tokens.length != _underlyingDecimals.length
        ) {
            revert InvalidConfig();
        }

        indexToken = BundlToken(_indexToken);

        for (uint256 i = 0; i < _tokens.length; i++) {
            underlyingTokens.push(_tokens[i]);
            amountsPerUnit.push(_amounts[i]);
            underlyingPoolKeys.push(_poolKeys[i]);
            usdcIsCurrency0.push(_usdcIs0[i]);
            underlyingDecimals.push(_underlyingDecimals[i]);
        }

        initialized = true;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HOOK CALLBACKS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Called after pool initialization — registers the IndexToken/USDC pool
    function afterInitialize(address, PoolKey calldata key, uint160, int24)
        external
        override
        onlyPoolManager
        returns (bytes4)
    {
        registeredPoolId = key.toId();
        return IHooks.afterInitialize.selector;
    }

    /// @notice Block direct liquidity additions — all liquidity is managed by the hook
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external view override onlyPoolManager returns (bytes4) {
        if (sender != address(this)) revert DirectLiquidityNotAllowed();
        return IHooks.beforeAddLiquidity.selector;
    }

    /// @notice Intercepts every swap in the IndexToken/USDC pool (NoOp pattern).
    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override onlyPoolManager whenInitialized returns (bytes4, BeforeSwapDelta, uint24) {
        // Verify this is our registered pool
        if (PoolId.unwrap(key.toId()) != PoolId.unwrap(registeredPoolId)) {
            revert PoolNotRegistered();
        }

        // Determine swap direction
        bool indexTokenIsCurrency0 = Currency.unwrap(key.currency0) == address(indexToken);
        bool isBuy;

        if (indexTokenIsCurrency0) {
            // currency0 = IndexToken, currency1 = USDC
            // zeroForOne = false means buying IndexToken with USDC (buy)
            isBuy = !params.zeroForOne;
        } else {
            // currency0 = USDC, currency1 = IndexToken
            // zeroForOne = true means selling USDC for IndexToken (buy)
            isBuy = params.zeroForOne;
        }

        uint256 absAmount =
            params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);

        if (isBuy) {
            return _handleBuy(params, absAmount, hookData);
        } else {
            return _handleSell(params, absAmount, hookData);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PUBLIC FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Redeem index tokens for proportional underlying assets
    function redeem(uint256 units) external override nonReentrant whenInitialized {
        if (units == 0) revert ZeroUnits();

        uint256 indexAmount = units * 1e18;

        // Burn index tokens from the user
        indexToken.burn(msg.sender, indexAmount);

        // Transfer proportional underlying assets to the user
        uint256[] memory amounts = new uint256[](underlyingTokens.length);
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            amounts[i] = units * amountsPerUnit[i];
            if (IERC20(underlyingTokens[i]).balanceOf(address(this)) < amounts[i]) {
                revert InsufficientBacking();
            }
            IERC20(underlyingTokens[i]).safeTransfer(msg.sender, amounts[i]);
        }

        emit Redeemed(msg.sender, units, amounts);
    }

    /// @notice Sweep accumulated ERC-6909 IndexToken claims from sells and burn the actual tokens
    /// @dev During sells, the hook mints ERC-6909 claims (PM bookkeeping) instead of burning
    ///      actual IndexToken. This function redeems those claims and burns the real tokens
    ///      to maintain correct supply economics. Can be called by anyone.
    function sweepAndBurnIndex() external nonReentrant whenInitialized {
        uint256 indexTokenCurrencyId = uint256(uint160(address(indexToken)));
        uint256 claims = poolManager.balanceOf(address(this), indexTokenCurrencyId);
        if (claims == 0) return;
        poolManager.unlock(abi.encode(claims));
    }

    /// @notice Callback for PoolManager.unlock — used by sweepAndBurnIndex
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(poolManager), "Only PM");
        uint256 claims = abi.decode(data, (uint256));
        uint256 indexTokenCurrencyId = uint256(uint160(address(indexToken)));
        // Burn ERC-6909 claims (adds positive delta — hook owes PM)
        poolManager.burn(address(this), indexTokenCurrencyId, claims);
        // Take actual IndexToken from PM (adds negative delta — PM owes hook)
        poolManager.take(Currency.wrap(address(indexToken)), address(this), claims);
        // Net delta = 0. Now burn the actual ERC-20 tokens to reduce supply.
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

    /// @notice Get sqrtPriceX96, tick, and liquidity for each underlying pool
    function getPoolStates()
        external
        view
        returns (uint160[] memory sqrtPrices, int24[] memory ticks, uint128[] memory liquidities)
    {
        uint256 n = underlyingTokens.length;
        sqrtPrices = new uint160[](n);
        ticks = new int24[](n);
        liquidities = new uint128[](n);

        for (uint256 i = 0; i < n; i++) {
            (sqrtPrices[i], ticks[i],,) = poolManager.getSlot0(underlyingPoolKeys[i].toId());
            liquidities[i] = poolManager.getLiquidity(underlyingPoolKeys[i].toId());
        }
    }

    /// @notice Calculate NAV per index unit in USDC (usdcDecimals)
    function getNavPerUnit() external view returns (uint256 navPerUnit) {
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(underlyingPoolKeys[i].toId());
            uint256 usdcValue = _getUsdcValueOfUnderlying(
                sqrtPriceX96,
                usdcIsCurrency0[i],
                amountsPerUnit[i],
                underlyingDecimals[i]
            );
            navPerUnit += usdcValue;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: BUY LOGIC (USDC → IndexToken)
    // ═══════════════════════════════════════════════════════════════════════

    function _handleBuy(IPoolManager.SwapParams calldata params, uint256 absAmount, bytes calldata hookData)
        internal
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint256 minOutput = 0;
        if (hookData.length > 0) {
            minOutput = abi.decode(hookData, (uint256));
        }

        bool isExactInput = params.amountSpecified < 0;

        uint256 usdcAmount;
        uint256 units;

        if (isExactInput) {
            // User wants to spend `absAmount` USDC
            usdcAmount = absAmount;

            // Buy underlying assets with the USDC
            units = _buyUnderlyingWithUsdc(usdcAmount);
        } else {
            // Exact output: user wants `absAmount` of IndexToken
            units = absAmount / 1e18;
            if (units == 0) revert ZeroUnits();

            // Calculate USDC needed and buy underlying assets
            usdcAmount = _buyUnderlyingForUnits(units);

            if (minOutput > 0 && usdcAmount > minOutput) revert TooMuchRequested();
        }

        uint256 indexTokensToMint = units * 1e18;
        if (isExactInput && minOutput > 0 && indexTokensToMint < minOutput) revert TooLittleReceived();

        // Mint index tokens and settle them to PoolManager (user receives them)
        indexToken.mint(address(this), indexTokensToMint);
        poolManager.sync(Currency.wrap(address(indexToken)));
        IERC20(address(indexToken)).transfer(address(poolManager), indexTokensToMint);
        poolManager.settle();

        emit Minted(msg.sender, units, usdcAmount);

        // Calculate the exact BeforeSwapDelta to instruct the PM
        // specified token   = -params.amountSpecified
        // unspecified token = Depends on whether we dictate the input or output
        int128 deltaUnspecified = isExactInput
            ? -int128(uint128(indexTokensToMint)) // Exact input: hook owes index tokens
            : int128(uint128(usdcAmount));        // Exact output: hook is owed USDC

        BeforeSwapDelta hookDelta =
            toBeforeSwapDelta(int128(-params.amountSpecified), deltaUnspecified);

        return (IHooks.beforeSwap.selector, hookDelta, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: SELL LOGIC (IndexToken → USDC)
    // ═══════════════════════════════════════════════════════════════════════

    function _handleSell(IPoolManager.SwapParams calldata params, uint256 absAmount, bytes calldata hookData)
        internal
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint256 minOutput = 0;
        if (hookData.length > 0) {
            minOutput = abi.decode(hookData, (uint256));
        }

        bool isExactInput = params.amountSpecified < 0;

        uint256 units;
        uint256 usdcReceived;

        if (isExactInput) {
            // User sells exact IndexToken amount
            units = absAmount / 1e18;
            if (units == 0) revert ZeroUnits();
        } else {
            // Exact output: user wants exact USDC amount
            usdcReceived = absAmount;
            // Estimate units needed
            units = _estimateUnitsForUsdc(usdcReceived);
            if (units == 0) revert ZeroUnits();
        }

        uint256 indexTokensToBurn = units * 1e18;
        if (!isExactInput && minOutput > 0 && indexTokensToBurn > minOutput) revert TooMuchRequested();

        // Use ERC-6909 mint to handle IndexToken delta accounting.
        // We can't use poolManager.take() here because PM has no IndexToken balance yet
        // (the router settles tokens AFTER beforeSwap returns).
        // mint() adjusts the delta without requiring actual ERC20 transfer.
        uint256 indexTokenCurrencyId = uint256(uint160(address(indexToken)));
        poolManager.mint(address(this), indexTokenCurrencyId, indexTokensToBurn);

        // Sell underlying assets for USDC
        uint256 actualUsdcReceived = _sellUnderlyingForUsdc(units);

        if (isExactInput) {
            usdcReceived = actualUsdcReceived;
            if (minOutput > 0 && usdcReceived < minOutput) revert TooLittleReceived();
        } else {
            if (actualUsdcReceived < usdcReceived) revert TooLittleReceived();
        }

        // Settle USDC to PoolManager (user receives them)
        poolManager.sync(Currency.wrap(usdc));
        IERC20(usdc).transfer(address(poolManager), usdcReceived);
        poolManager.settle();

        emit Sold(msg.sender, units, usdcReceived);

        // deltaUnspecified: NEGATIVE because the hook PROVIDES USDC to the swap
        // (the hook settled USDC to PM, and this delta tells PM the hook is providing it)
        int128 deltaUnspecified = isExactInput
            ? -int128(uint128(usdcReceived))        // Exact input: hook provides USDC
            : -int128(uint128(indexTokensToBurn));   // Exact output: hook provides index tokens

        BeforeSwapDelta hookDelta =
            toBeforeSwapDelta(int128(-params.amountSpecified), deltaUnspecified);

        return (IHooks.beforeSwap.selector, hookDelta, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: UNDERLYING SWAP HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Buy underlying tokens with a given amount of USDC
    /// @return units The number of complete index units purchased
    function _buyUnderlyingWithUsdc(uint256 totalUsdc) internal returns (uint256 units) {
        uint256 numTokens = underlyingTokens.length;
        uint256 usdcPerToken = totalUsdc / numTokens;

        // Find the minimum units achievable across all underlying tokens
        units = type(uint256).max;

        for (uint256 i = 0; i < numTokens; i++) {
            uint256 underlyingReceived = _swapExactUsdcForUnderlying(i, usdcPerToken);
            uint256 unitsFromThis = underlyingReceived / amountsPerUnit[i];
            if (unitsFromThis < units) {
                units = unitsFromThis;
            }
        }

        if (units == 0) revert ZeroUnits();
    }

    /// @notice Buy exact underlying amounts for a given number of units
    /// @return totalUsdcSpent Total USDC spent across all underlying swaps
    function _buyUnderlyingForUnits(uint256 units) internal returns (uint256 totalUsdcSpent) {
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            uint256 underlyingNeeded = units * amountsPerUnit[i];
            totalUsdcSpent += _swapUsdcForExactUnderlying(i, underlyingNeeded);
        }
    }

    /// @notice Sell underlying tokens for USDC
    /// @return usdcReceived Total USDC received
    function _sellUnderlyingForUsdc(uint256 units) internal returns (uint256 usdcReceived) {
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            uint256 underlyingAmount = units * amountsPerUnit[i];
            if (IERC20(underlyingTokens[i]).balanceOf(address(this)) < underlyingAmount) {
                revert InsufficientBacking();
            }
            usdcReceived += _swapExactUnderlyingForUsdc(i, underlyingAmount);
        }
    }

    /// @notice Estimate units needed for a target USDC amount (for exact-output sells)
    function _estimateUnitsForUsdc(uint256 targetUsdc) internal view returns (uint256 units) {
        uint256 navPerUnit = 0;
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(underlyingPoolKeys[i].toId());
            uint256 usdcValue = _getUsdcValueOfUnderlying(
                sqrtPriceX96,
                usdcIsCurrency0[i],
                amountsPerUnit[i],
                underlyingDecimals[i]
            );
            navPerUnit += usdcValue;
        }

        if (navPerUnit == 0) return 1;
        units = (targetUsdc + navPerUnit - 1) / navPerUnit; // Round up
        if (units == 0) units = 1;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: ATOMIC SWAP EXECUTION ON UNDERLYING POOLS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Swap exact USDC input for underlying token.
    /// @dev After the swap, the hook owes USDC to PoolManager (negative delta on USDC).
    ///      We must settle that debt immediately via sync/transfer/settle before returning.
    function _swapExactUsdcForUnderlying(uint256 tokenIndex, uint256 usdcAmount)
        internal
        returns (uint256 underlyingReceived)
    {
        PoolKey memory poolKey = underlyingPoolKeys[tokenIndex];
        bool zeroForOne = usdcIsCurrency0[tokenIndex];

        // Execute swap: exact input
        BalanceDelta delta = poolManager.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(usdcAmount),
                sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1
            }),
            ""
        );

        // Extract the underlying amount received
        int128 outputAmount = zeroForOne ? delta.amount1() : delta.amount0();
        underlyingReceived = uint256(uint128(outputAmount > 0 ? outputAmount : -outputAmount));

        // Settle USDC owed to PoolManager (hook is paying for the swap)
        poolManager.sync(Currency.wrap(usdc));
        IERC20(usdc).transfer(address(poolManager), usdcAmount);
        poolManager.settle();

        // Take the underlying tokens from PoolManager into this contract
        poolManager.take(Currency.wrap(underlyingTokens[tokenIndex]), address(this), underlyingReceived);
    }

    /// @notice Swap USDC for exact underlying token output.
    /// @dev After the swap, the hook owes USDC to PoolManager (negative delta on USDC).
    ///      We must settle that debt immediately via sync/transfer/settle before returning.
    function _swapUsdcForExactUnderlying(uint256 tokenIndex, uint256 underlyingAmount)
        internal
        returns (uint256 usdcSpent)
    {
        PoolKey memory poolKey = underlyingPoolKeys[tokenIndex];
        bool zeroForOne = usdcIsCurrency0[tokenIndex];

        // Execute swap: exact output
        BalanceDelta delta = poolManager.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: int256(underlyingAmount),
                sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1
            }),
            ""
        );

        // Calculate actual USDC owed (may differ slightly from estimate due to price impact)
        int128 inputAmount = zeroForOne ? delta.amount0() : delta.amount1();
        usdcSpent = uint256(uint128(inputAmount < 0 ? -inputAmount : inputAmount));

        // Settle USDC owed to PoolManager
        poolManager.sync(Currency.wrap(usdc));
        IERC20(usdc).transfer(address(poolManager), usdcSpent);
        poolManager.settle();

        // Take the underlying tokens from PoolManager into this contract
        poolManager.take(Currency.wrap(underlyingTokens[tokenIndex]), address(this), underlyingAmount);
    }

    /// @notice Swap exact underlying token input for USDC
    function _swapExactUnderlyingForUsdc(uint256 tokenIndex, uint256 underlyingAmount)
        internal
        returns (uint256 usdcReceived)
    {
        PoolKey memory poolKey = underlyingPoolKeys[tokenIndex];
        // If USDC is currency0, underlying is currency1 → swap 1→0 (zeroForOne = false)
        bool zeroForOne = !usdcIsCurrency0[tokenIndex];

        // Execute swap: exact input
        BalanceDelta delta = poolManager.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(underlyingAmount),
                sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1
            }),
            ""
        );

        // Extract USDC received
        int128 outputAmount = zeroForOne ? delta.amount1() : delta.amount0();
        usdcReceived = uint256(uint128(outputAmount > 0 ? outputAmount : -outputAmount));

        // Settle underlying tokens we owe to PoolManager
        poolManager.sync(Currency.wrap(underlyingTokens[tokenIndex]));
        IERC20(underlyingTokens[tokenIndex]).transfer(address(poolManager), underlyingAmount);
        poolManager.settle();

        // Take USDC received from PoolManager
        poolManager.take(Currency.wrap(usdc), address(this), usdcReceived);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: PRICE HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get the USDC value of a specific underlying amount using the pool's sqrt price.
    /// @dev Normalizes the decimal difference between the underlying token and USDC so that
    ///      the returned value is always expressed in USDC units (usdcDecimals).
    ///      sqrtPriceX96 encodes the raw token ratio without decimal adjustment, so we must
    ///      scale the result by 10^(underlyingDecimals - usdcDecimals) or its inverse.
    function _getUsdcValueOfUnderlying(
        uint160 sqrtPriceX96,
        bool usdcIs0,
        uint256 underlyingAmount,
        uint8 tokenDecimals
    ) internal view returns (uint256 usdcValue) {
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        uint256 rawValue;

        if (usdcIs0) {
            // USDC is token0, underlying is token1
            // price (token0 per token1) = 2^192 / sqrtPrice^2
            // usdcValue = underlyingAmount * 2^192 / sqrtPrice^2
            uint256 intermediate = FullMath.mulDiv(underlyingAmount, 1 << 96, sqrtPrice);
            rawValue = FullMath.mulDiv(intermediate, 1 << 96, sqrtPrice);
        } else {
            // USDC is token1, underlying is token0
            // price (token1 per token0) = sqrtPrice^2 / 2^192
            // usdcValue = underlyingAmount * sqrtPrice^2 / 2^192
            uint256 intermediate = FullMath.mulDiv(underlyingAmount, sqrtPrice, 1 << 96);
            rawValue = FullMath.mulDiv(intermediate, sqrtPrice, 1 << 96);
        }

        // Normalize decimal difference so result is in usdcDecimals units.
        // sqrtPriceX96 reflects raw token amounts, so if tokenDecimals != usdcDecimals
        // the rawValue is off by 10^(tokenDecimals - usdcDecimals).
        if (tokenDecimals > usdcDecimals) {
            usdcValue = rawValue / (10 ** (tokenDecimals - usdcDecimals));
        } else if (usdcDecimals > tokenDecimals) {
            usdcValue = rawValue * (10 ** (usdcDecimals - tokenDecimals));
        } else {
            usdcValue = rawValue;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // UNIMPLEMENTED HOOK CALLBACKS
    // ═══════════════════════════════════════════════════════════════════════

    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        pure
        override
        returns (bytes4, int128)
    {
        revert HookNotImplemented();
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }
}
