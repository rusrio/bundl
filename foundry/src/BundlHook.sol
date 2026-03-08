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

    /// @notice The registered IndexToken/USDC pool
    PoolId public registeredPoolId;
    bool public initialized;

    /// @notice USDC token address
    address public immutable usdc;

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

    constructor(IPoolManager _poolManager, address _usdc) {
        poolManager = _poolManager;
        usdc = _usdc;

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
        bool[] calldata _usdcIs0
    ) external {
        if (initialized) revert AlreadyInitialized();
        if (
            _tokens.length == 0 || _tokens.length != _amounts.length || _tokens.length != _poolKeys.length
                || _tokens.length != _usdcIs0.length
        ) {
            revert InvalidConfig();
        }

        indexToken = BundlToken(_indexToken);

        for (uint256 i = 0; i < _tokens.length; i++) {
            underlyingTokens.push(_tokens[i]);
            amountsPerUnit.push(_amounts[i]);
            underlyingPoolKeys.push(_poolKeys[i]);
            usdcIsCurrency0.push(_usdcIs0[i]);
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
        bytes calldata
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
            return _handleBuy(params, absAmount);
        } else {
            return _handleSell(params, absAmount);
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

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: BUY LOGIC (USDC → IndexToken)
    // ═══════════════════════════════════════════════════════════════════════

    function _handleBuy(IPoolManager.SwapParams calldata params, uint256 absAmount)
        internal
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        bool isExactInput = params.amountSpecified < 0;

        uint256 usdcAmount;
        uint256 units;

        if (isExactInput) {
            // User wants to spend `absAmount` USDC
            usdcAmount = absAmount;

            // Take USDC from PoolManager (the user's input flows through PM)
            poolManager.take(Currency.wrap(usdc), address(this), usdcAmount);

            // Buy underlying assets with the USDC
            units = _buyUnderlyingWithUsdc(usdcAmount);
        } else {
            // Exact output: user wants `absAmount` of IndexToken
            units = absAmount / 1e18;
            if (units == 0) revert ZeroUnits();

            // Calculate USDC needed and buy underlying assets
            usdcAmount = _buyUnderlyingForUnits(units);

            // Take USDC from PoolManager
            poolManager.take(Currency.wrap(usdc), address(this), usdcAmount);
        }

        uint256 indexTokensToMint = units * 1e18;

        // Mint index tokens and settle them to PoolManager (user receives them)
        indexToken.mint(address(this), indexTokensToMint);
        poolManager.sync(Currency.wrap(address(indexToken)));
        IERC20(address(indexToken)).transfer(address(poolManager), indexTokensToMint);
        poolManager.settle();

        emit Minted(msg.sender, units, usdcAmount);

        // NoOp: cancel the AMM execution entirely
        BeforeSwapDelta hookDelta =
            toBeforeSwapDelta(int128(-params.amountSpecified), int128(params.amountSpecified));

        return (IHooks.beforeSwap.selector, hookDelta, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: SELL LOGIC (IndexToken → USDC)
    // ═══════════════════════════════════════════════════════════════════════

    function _handleSell(IPoolManager.SwapParams calldata params, uint256 absAmount)
        internal
        returns (bytes4, BeforeSwapDelta, uint24)
    {
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

        // Take IndexToken from PoolManager (user's input)
        poolManager.take(Currency.wrap(address(indexToken)), address(this), indexTokensToBurn);
        // Burn them
        indexToken.burn(address(this), indexTokensToBurn);

        // Sell underlying assets for USDC
        usdcReceived = _sellUnderlyingForUsdc(units);

        // Settle USDC to PoolManager (user receives them)
        poolManager.sync(Currency.wrap(usdc));
        IERC20(usdc).transfer(address(poolManager), usdcReceived);
        poolManager.settle();

        emit Sold(msg.sender, units, usdcReceived);

        // NoOp delta
        BeforeSwapDelta hookDelta =
            toBeforeSwapDelta(int128(-params.amountSpecified), int128(params.amountSpecified));

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
        // Calculate NAV per unit based on spot prices
        uint256 navPerUnit = 0;
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(underlyingPoolKeys[i].toId());
            uint256 price = _priceFromSqrtX96(sqrtPriceX96, usdcIsCurrency0[i]);
            navPerUnit += (amountsPerUnit[i] * price) / 1e18;
        }

        if (navPerUnit == 0) return 1;
        units = (targetUsdc + navPerUnit - 1) / navPerUnit; // Round up
        if (units == 0) units = 1;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: ATOMIC SWAP EXECUTION ON UNDERLYING POOLS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Swap exact USDC input for underlying token
    function _swapExactUsdcForUnderlying(uint256 tokenIndex, uint256 usdcAmount)
        internal
        returns (uint256 underlyingReceived)
    {
        PoolKey memory poolKey = underlyingPoolKeys[tokenIndex];
        bool zeroForOne = usdcIsCurrency0[tokenIndex];

        // Settle USDC to PoolManager for the underlying swap
        poolManager.sync(Currency.wrap(usdc));
        IERC20(usdc).transfer(address(poolManager), usdcAmount);
        poolManager.settle();

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

        // Take the underlying tokens from PoolManager
        poolManager.take(Currency.wrap(underlyingTokens[tokenIndex]), address(this), underlyingReceived);
    }

    /// @notice Swap USDC for exact underlying token output
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

        // Calculate USDC owed
        int128 inputAmount = zeroForOne ? delta.amount0() : delta.amount1();
        usdcSpent = uint256(uint128(inputAmount < 0 ? -inputAmount : inputAmount));

        // Settle USDC to PoolManager
        poolManager.sync(Currency.wrap(usdc));
        IERC20(usdc).transfer(address(poolManager), usdcSpent);
        poolManager.settle();

        // Take the underlying tokens
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

        // Settle underlying to PoolManager
        poolManager.sync(Currency.wrap(underlyingTokens[tokenIndex]));
        IERC20(underlyingTokens[tokenIndex]).transfer(address(poolManager), underlyingAmount);
        poolManager.settle();

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

        // Take USDC
        poolManager.take(Currency.wrap(usdc), address(this), usdcReceived);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: PRICE HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Convert sqrtPriceX96 to a usable price
    function _priceFromSqrtX96(uint160 sqrtPriceX96, bool usdcIs0) internal pure returns (uint256 price) {
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        // price of token1 in terms of token0 = (sqrtPriceX96)^2 / 2^192
        price = (sqrtPrice * sqrtPrice) >> 192;

        if (usdcIs0) {
            // price = underlying/USDC → we need USDC/underlying → invert
            if (price > 0) {
                price = 1e36 / price;
            }
        }
        // If USDC is currency1, price = token1/token0 already = USDC/underlying ✓
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
