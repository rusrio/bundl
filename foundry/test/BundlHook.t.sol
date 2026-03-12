// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

import {BundlHook} from "../src/BundlHook.sol";
import {BundlFactory} from "../src/BundlFactory.sol";
import {BundlToken} from "../src/BundlToken.sol";

contract BundlHookTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    PoolManager public manager;
    PoolSwapTest public swapRouter;
    PoolModifyLiquidityTest public modifyLiqRouter;

    MockERC20 public usdc;
    MockERC20 public wbtc;
    MockERC20 public weth;

    BundlHook public hook;
    BundlToken public indexToken;

    PoolKey public indexPoolKey;
    PoolKey public wbtcUsdcPoolKey;
    PoolKey public wethUsdcPoolKey;

    address public alice = address(0xA11CE);

    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint8   constant USDC_DECIMALS  = 6;
    uint256 constant SWAP_USDC_AMOUNT = 100e6;

    // Must match BundlHook constructor Hooks.Permissions exactly.
    uint160 constant HOOK_FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG
        | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
        | Hooks.BEFORE_SWAP_FLAG
        | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        | Hooks.AFTER_SWAP_FLAG
    );

    // Second hook address for isolation tests: extra bit outside ALL_HOOK_MASK (14 bits)
    uint160 constant HOOK_FLAGS_2 = HOOK_FLAGS | (1 << 20);

    function setUp() public {
        manager = new PoolManager(address(this));
        swapRouter = new PoolSwapTest(manager);
        modifyLiqRouter = new PoolModifyLiquidityTest(manager);

        usdc = new MockERC20("USD Coin", "USDC", USDC_DECIMALS);
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        usdc.mint(address(this), type(uint128).max);
        usdc.mint(alice, 100_000e6);
        wbtc.mint(address(this), type(uint128).max);
        weth.mint(address(this), type(uint128).max);

        deployCodeTo(
            "BundlHook.sol:BundlHook",
            abi.encode(manager, address(usdc), USDC_DECIMALS),
            address(HOOK_FLAGS)
        );
        hook = BundlHook(address(HOOK_FLAGS));

        indexToken = new BundlToken("Bundl BTC-ETH", "bBTC-ETH", address(hook));

        _setupUnderlyingPools();
        _initializeHook();
        _initializeIndexPool();

        usdc.approve(address(swapRouter), type(uint256).max);
        IERC20Minimal(address(indexToken)).approve(address(swapRouter), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS: Initialization
    // ═══════════════════════════════════════════════════════════════════════

    function test_hookIsInitialized() public view {
        assertTrue(hook.initialized());
        assertEq(address(hook.indexToken()), address(indexToken));
    }

    function test_underlyingConfig() public view {
        address[] memory tokens = hook.getUnderlyingTokens();
        assertEq(tokens.length, 2);
        uint256[] memory amounts = hook.getAmountsPerUnit();
        assertEq(amounts.length, 2);
        uint256[] memory weights = hook.getUnderlyingWeightsBps();
        assertEq(weights.length, 2);
        assertEq(weights[0], 5000);
        assertEq(weights[1], 5000);
    }

    function test_hookAddressHasCorrectFlags() public view {
        assertTrue(uint160(address(hook)) & Hooks.BEFORE_SWAP_FLAG != 0);
        assertTrue(uint160(address(hook)) & Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG != 0);
        assertTrue(uint160(address(hook)) & Hooks.AFTER_INITIALIZE_FLAG != 0);
        assertTrue(uint160(address(hook)) & Hooks.BEFORE_ADD_LIQUIDITY_FLAG != 0);
        assertTrue(uint160(address(hook)) & Hooks.AFTER_SWAP_FLAG != 0);
    }

    function test_cannotReinitialize() public {
        address[] memory tokens   = new address[](1);
        uint256[] memory amounts  = new uint256[](1);
        uint256[] memory weights  = new uint256[](1);
        PoolKey[] memory poolKeys = new PoolKey[](1);
        bool[]    memory usdcIs0  = new bool[](1);
        uint8[]   memory decimals = new uint8[](1);
        weights[0] = 10000;
        vm.expectRevert(BundlHook.AlreadyInitialized.selector);
        hook.initialize(address(indexToken), tokens, amounts, weights, poolKeys, usdcIs0, decimals);
    }

    function test_invalidWeightsRevert() public {
        deployCodeTo(
            "BundlHook.sol:BundlHook",
            abi.encode(manager, address(usdc), USDC_DECIMALS),
            address(HOOK_FLAGS_2)
        );
        BundlHook hook2 = BundlHook(address(HOOK_FLAGS_2));

        address[] memory tokens   = new address[](2);
        uint256[] memory amounts  = new uint256[](2);
        uint256[] memory weights  = new uint256[](2);
        PoolKey[] memory poolKeys = new PoolKey[](2);
        bool[]    memory usdcIs0  = new bool[](2);
        uint8[]   memory decimals = new uint8[](2);

        tokens[0] = address(wbtc);     tokens[1] = address(weth);
        amounts[0] = 1e6;              amounts[1] = 1e6;
        weights[0] = 3000;             weights[1] = 3000;
        poolKeys[0] = wbtcUsdcPoolKey; poolKeys[1] = wethUsdcPoolKey;
        decimals[0] = 8;               decimals[1] = 18;

        vm.expectRevert(BundlHook.InvalidWeights.selector);
        hook2.initialize(address(indexToken), tokens, amounts, weights, poolKeys, usdcIs0, decimals);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS: Redeem
    // ═══════════════════════════════════════════════════════════════════════

    function test_redeemGivesUnderlyingAssets() public {
        uint256[] memory amounts = hook.getAmountsPerUnit();
        uint256 indexAmount = 2e18; // 2 full units

        wbtc.transfer(address(hook), amounts[0] * 2);
        weth.transfer(address(hook), amounts[1] * 2);

        vm.prank(address(hook));
        indexToken.mint(alice, indexAmount);

        uint256 wbtcBefore = wbtc.balanceOf(alice);
        uint256 wethBefore = weth.balanceOf(alice);

        vm.startPrank(alice);
        IERC20Minimal(address(indexToken)).approve(address(hook), indexAmount);
        hook.redeem(indexAmount);
        vm.stopPrank();

        assertEq(wbtc.balanceOf(alice), wbtcBefore + amounts[0] * 2);
        assertEq(weth.balanceOf(alice), wethBefore + amounts[1] * 2);
        assertEq(indexToken.balanceOf(alice), 0);
    }

    function test_revertRedeemZeroUnits() public {
        vm.prank(alice);
        vm.expectRevert(BundlHook.ZeroUnits.selector);
        hook.redeem(0);
    }

    function test_revertRedeemInsufficientBacking() public {
        vm.prank(address(hook));
        indexToken.mint(alice, 1e18);
        vm.startPrank(alice);
        IERC20Minimal(address(indexToken)).approve(address(hook), 1e18);
        vm.expectRevert(BundlHook.InsufficientBacking.selector);
        hook.redeem(1e18);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS: Access Control
    // ═══════════════════════════════════════════════════════════════════════

    function test_revertDirectCallToBeforeSwap() public {
        vm.prank(alice);
        vm.expectRevert(BundlHook.NotPoolManager.selector);
        hook.beforeSwap(
            address(0),
            indexPoolKey,
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -1000, sqrtPriceLimitX96: 0}),
            ""
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS: View Functions
    // ═══════════════════════════════════════════════════════════════════════

    function test_getTotalBacking() public view {
        uint256[] memory backing = hook.getTotalBacking();
        assertEq(backing.length, 2);
        assertEq(backing[0], 0);
        assertEq(backing[1], 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS: Block Direct Liquidity
    // ═══════════════════════════════════════════════════════════════════════

    function test_revertDirectLiquidityAddition() public {
        usdc.approve(address(modifyLiqRouter), type(uint256).max);
        vm.expectRevert();
        modifyLiqRouter.modifyLiquidity(
            indexPoolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -887220,
                tickUpper: 887220,
                liquidityDelta: 1000e6,
                salt: bytes32(0)
            }),
            ""
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS: Buy
    // ═══════════════════════════════════════════════════════════════════════

    function test_buyExactUsdcForIndex() public {
        usdc.mint(alice, SWAP_USDC_AMOUNT);
        vm.prank(alice);
        usdc.approve(address(swapRouter), SWAP_USDC_AMOUNT);

        bool zeroForOne = Currency.unwrap(indexPoolKey.currency0) == address(usdc);

        uint256 usdcBefore   = usdc.balanceOf(alice);
        uint256 indexBefore  = indexToken.balanceOf(alice);

        vm.prank(alice);
        swapRouter.swap(
            indexPoolKey,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(SWAP_USDC_AMOUNT),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );

        uint256 indexReceived = indexToken.balanceOf(alice) - indexBefore;
        uint256 usdcSpent     = usdcBefore - usdc.balanceOf(alice);
        console.log("[BUY]  USDC spent:     ", usdcSpent);
        console.log("[BUY]  Index received: ", indexReceived);
        assertTrue(indexReceived > 0, "Alice did not receive IndexToken");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS: Sell
    // ═══════════════════════════════════════════════════════════════════════

    function test_sellExactIndexForUsdc() public {
        // First buy some index tokens
        test_buyExactUsdcForIndex();

        uint256 indexBalance = indexToken.balanceOf(alice);
        assertTrue(indexBalance > 0, "Alice has no index tokens to sell");

        console.log("[SELL] Index to sell:          ", indexBalance);
        console.log("[SELL] Hook WBTC backing:      ", wbtc.balanceOf(address(hook)));
        console.log("[SELL] Hook WETH backing:      ", weth.balanceOf(address(hook)));
        console.log("[SELL] Hook USDC balance:      ", usdc.balanceOf(address(hook)));
        console.log("[SELL] totalSupply before:     ", indexToken.totalSupply());

        vm.prank(alice);
        IERC20Minimal(address(indexToken)).approve(address(swapRouter), indexBalance);

        bool zeroForOne = Currency.unwrap(indexPoolKey.currency0) == address(usdc);
        uint256 usdcBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        swapRouter.swap(
            indexPoolKey,
            IPoolManager.SwapParams({
                zeroForOne: !zeroForOne,
                amountSpecified: -int256(indexBalance),
                sqrtPriceLimitX96: !zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );

        uint256 usdcReceived = usdc.balanceOf(alice) - usdcBefore;
        console.log("[SELL] USDC received:          ", usdcReceived);
        console.log("[SELL] totalSupply after:      ", indexToken.totalSupply());
        console.log("[SELL] Alice index remaining:  ", indexToken.balanceOf(alice));

        assertTrue(usdcReceived > 0, "Alice did not receive USDC");
        assertEq(indexToken.balanceOf(alice), 0, "Alice should have sold all IndexToken");
        assertEq(indexToken.totalSupply(), 0, "totalSupply should be 0 after full sell");
    }

    function test_slippageRevert() public {
        usdc.mint(alice, SWAP_USDC_AMOUNT);
        vm.prank(alice);
        usdc.approve(address(swapRouter), SWAP_USDC_AMOUNT);

        bool zeroForOne = Currency.unwrap(indexPoolKey.currency0) == address(usdc);
        bytes memory hookData = abi.encode(uint256(9999999999e18));

        vm.prank(alice);
        vm.expectRevert();
        swapRouter.swap(
            indexPoolKey,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(SWAP_USDC_AMOUNT),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: SETUP HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    function _setupUnderlyingPools() internal {
        usdc.approve(address(modifyLiqRouter), type(uint256).max);
        wbtc.approve(address(modifyLiqRouter), type(uint256).max);
        weth.approve(address(modifyLiqRouter), type(uint256).max);

        (Currency c0, Currency c1) = _sortCurrencies(address(wbtc), address(usdc));
        wbtcUsdcPoolKey = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))});
        manager.initialize(wbtcUsdcPoolKey, SQRT_PRICE_1_1);
        modifyLiqRouter.modifyLiquidity(
            wbtcUsdcPoolKey,
            IPoolManager.ModifyLiquidityParams({tickLower: -887220, tickUpper: 887220, liquidityDelta: 100_000_000e18, salt: bytes32(0)}),
            ""
        );

        (c0, c1) = _sortCurrencies(address(weth), address(usdc));
        wethUsdcPoolKey = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))});
        manager.initialize(wethUsdcPoolKey, SQRT_PRICE_1_1);
        modifyLiqRouter.modifyLiquidity(
            wethUsdcPoolKey,
            IPoolManager.ModifyLiquidityParams({tickLower: -887220, tickUpper: 887220, liquidityDelta: 100_000_000e18, salt: bytes32(0)}),
            ""
        );
    }

    function _initializeHook() internal {
        address[] memory tokens   = new address[](2);
        uint256[] memory amounts  = new uint256[](2);
        uint256[] memory weights  = new uint256[](2);
        PoolKey[] memory poolKeys = new PoolKey[](2);
        bool[]    memory usdcIs0  = new bool[](2);
        uint8[]   memory decimals = new uint8[](2);

        tokens[0]   = address(wbtc); amounts[0] = 1e6; weights[0] = 5000;
        poolKeys[0] = wbtcUsdcPoolKey;
        usdcIs0[0]  = Currency.unwrap(wbtcUsdcPoolKey.currency0) == address(usdc);
        decimals[0] = 8;

        tokens[1]   = address(weth); amounts[1] = 1e6; weights[1] = 5000;
        poolKeys[1] = wethUsdcPoolKey;
        usdcIs0[1]  = Currency.unwrap(wethUsdcPoolKey.currency0) == address(usdc);
        decimals[1] = 18;

        hook.initialize(address(indexToken), tokens, amounts, weights, poolKeys, usdcIs0, decimals);
    }

    function _initializeIndexPool() internal {
        (Currency c0, Currency c1) = _sortCurrencies(address(indexToken), address(usdc));
        indexPoolKey = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(hook))});
        manager.initialize(indexPoolKey, SQRT_PRICE_1_1);
    }

    function _sortCurrencies(address a, address b) internal pure returns (Currency, Currency) {
        return a < b ? (Currency.wrap(a), Currency.wrap(b)) : (Currency.wrap(b), Currency.wrap(a));
    }
}

interface IERC20Minimal {
    function approve(address spender, uint256 amount) external returns (bool);
}
