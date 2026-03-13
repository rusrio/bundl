// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {BundlFactory} from "../src/BundlFactory.sol";

/// @title DeployBtcEthUniScript
/// @notice Deploys a second BundlHook index: 40% BTC / 30% ETH / 30% UNI
/// @dev Reads existing infrastructure from env vars (FACTORY_ADDRESS, etc.)
///      Writes new addresses to deploy2.json
contract DeployBtcEthUniScript is Script {

    // ── Simulated prices ────────────────────────────────────────────────
    // BTC  ≈ $85,000  (8 dec)  → 40% of $100 = $40  → 40/85000 BTC  = 47058 satoshis
    // ETH  ≈ $2,000   (18 dec) → 30% of $100 = $30  → 30/2000  ETH  = 0.015e18
    // UNI  ≈ $10      (18 dec) → 30% of $100 = $30  → 30/10    UNI  = 3e18
    uint256 constant AMOUNTS_WBTC = 47_058;
    uint256 constant AMOUNTS_WETH = 15_000_000_000_000_000;
    uint256 constant AMOUNTS_WUNI = 3_000_000_000_000_000_000;

    // ── sqrtPriceX96 for WBTC/USDC and WETH/USDC (same as Deploy.s.sol) ────
    uint160 constant SQRT_PRICE_WBTC_USDC_IS0 = 2717503554927417600000000000;
    uint160 constant SQRT_PRICE_WBTC_USDC_IS1 = 2309878021688305200000000000000;
    uint160 constant SQRT_PRICE_WETH_USDC_IS0 = 1771595571142957200000000000000000;
    uint160 constant SQRT_PRICE_WETH_USDC_IS1 = 3543191142285914300000000;

    // ── sqrtPriceX96 for WUNI/USDC ─────────────────────────────────────
    // WUNI=c0 (18 dec), USDC=c1 (6 dec), UNI ≈ $10
    // price_raw = 10e6 / 1e18 = 1e-11
    // sqrtPriceX96 = sqrt(1e-11) * 2^96 = 250541448375047931186413796
    uint160 constant SQRT_PRICE_WUNI_USDC_IS1 = 250541448375047931186413796;
    // If USDC is c0 (usdc < wuni address):
    // price_raw = 1e18 / 10e6 = 1e11
    // sqrtPriceX96 = sqrt(1e11) * 2^96 = 25054144837504793118641379600000
    uint160 constant SQRT_PRICE_WUNI_USDC_IS0 = 25054144837504793118641379600000;

    int256  constant LIQ_WBTC_POOL = 17_149_858_512;
    int256  constant LIQ_WETH_POOL = 11_180_339_887_498_948;
    int256  constant LIQ_WUNI_POOL = 2_000_000_000_000_000_000;

    // tick range centered around tick -230270 (UNI=$10 with 18dec/6dec)
    int24 constant TICK_LOWER_WUNI = -276360;
    int24 constant TICK_UPPER_WUNI = -184140;

    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function run() public {
        uint256 deployerKey        = vm.envUint("PRIVATE_KEY");
        address deployer           = vm.addr(deployerKey);
        address factoryAddr        = vm.envAddress("FACTORY_ADDRESS");
        address usdcAddr           = vm.envAddress("USDC_ADDRESS");
        address wbtcAddr           = vm.envAddress("WBTC_ADDRESS");
        address wethAddr           = vm.envAddress("WETH_ADDRESS");
        address modLiqAddr         = vm.envAddress("MODIFY_LIQ_ROUTER_ADDRESS");

        console.log("Deploying BTC-ETH-UNI index on chainId:", block.chainid);
        console.log("Deployer:", deployer);

        BundlFactory factory           = BundlFactory(factoryAddr);
        IPoolManager poolManager       = factory.poolManager();
        PoolModifyLiquidityTest modLiq = PoolModifyLiquidityTest(modLiqAddr);

        vm.startBroadcast(deployerKey);

        // ── Deploy mock WUNI ────────────────────────────────────────────
        console.log("Deploying mock WUNI...");
        MockERC20 wuniMock = new MockERC20("Mock Uniswap", "WUNI", 18);
        wuniMock.mint(deployer, 100_000e18);
        address wuniAddr = address(wuniMock);
        console.log("WUNI deployed at:", wuniAddr);

        // ── Initialize WUNI/USDC underlying pool ────────────────────────
        (Currency c0, Currency c1) = _sort(wuniAddr, usdcAddr);
        bool usdcIs0Wuni = Currency.unwrap(c0) == usdcAddr;

        PoolKey memory wuniPool = PoolKey({
            currency0:   c0,
            currency1:   c1,
            fee:         3000,
            tickSpacing: 60,
            hooks:       IHooks(address(0))
        });

        poolManager.initialize(
            wuniPool,
            usdcIs0Wuni ? SQRT_PRICE_WUNI_USDC_IS0 : SQRT_PRICE_WUNI_USDC_IS1
        );

        MockERC20(usdcAddr).approve(address(modLiq), type(uint256).max);
        wuniMock.approve(address(modLiq), type(uint256).max);
        modLiq.modifyLiquidity(
            wuniPool,
            IPoolManager.ModifyLiquidityParams({
                tickLower:      TICK_LOWER_WUNI,
                tickUpper:      TICK_UPPER_WUNI,
                liquidityDelta: LIQ_WUNI_POOL,
                salt:           0
            }),
            ""
        );
        console.log("WUNI/USDC pool initialized with liquidity.");

        // ── Reuse existing WBTC/USDC and WETH/USDC pools ───────────────
        (Currency bc0, Currency bc1) = _sort(wbtcAddr, usdcAddr);
        bool usdcIs0Wbtc = Currency.unwrap(bc0) == usdcAddr;
        PoolKey memory wbtcPool = PoolKey({
            currency0:   bc0,
            currency1:   bc1,
            fee:         3000,
            tickSpacing: 60,
            hooks:       IHooks(address(0))
        });

        (Currency ec0, Currency ec1) = _sort(wethAddr, usdcAddr);
        bool usdcIs0Weth = Currency.unwrap(ec0) == usdcAddr;
        PoolKey memory wethPool = PoolKey({
            currency0:   ec0,
            currency1:   ec1,
            fee:         3000,
            tickSpacing: 60,
            hooks:       IHooks(address(0))
        });

        // ── Build createBundl params ────────────────────────────────────
        address[] memory uTokens        = new address[](3);
        uint256[] memory amountsPerUnit = new uint256[](3);
        uint256[] memory weightsBps     = new uint256[](3);
        PoolKey[]  memory poolKeys      = new PoolKey[](3);
        bool[]     memory usdcIs0       = new bool[](3);
        uint8[]    memory decimals      = new uint8[](3);

        uTokens[0] = wbtcAddr; uTokens[1] = wethAddr; uTokens[2] = wuniAddr;
        amountsPerUnit[0] = AMOUNTS_WBTC;
        amountsPerUnit[1] = AMOUNTS_WETH;
        amountsPerUnit[2] = AMOUNTS_WUNI;
        weightsBps[0] = 4000; weightsBps[1] = 3000; weightsBps[2] = 3000;
        poolKeys[0]  = wbtcPool; poolKeys[1] = wethPool; poolKeys[2] = wuniPool;
        usdcIs0[0]   = usdcIs0Wbtc;
        usdcIs0[1]   = usdcIs0Weth;
        usdcIs0[2]   = usdcIs0Wuni;
        decimals[0]  = 8; decimals[1] = 18; decimals[2] = 18;

        console.log("Deploying bBEU Bundl index...");
        (address hookAddr, address tokenAddr,) = factory.createBundl(
            BundlFactory.CreateBundlParams({
                name:             "BTC-ETH-UNI Index",
                symbol:           "bBEU",
                underlyingTokens: uTokens,
                amountsPerUnit:   amountsPerUnit,
                weightsBps:       weightsBps,
                underlyingPools:  poolKeys,
                usdcIs0:          usdcIs0,
                tokenDecimals:    decimals,
                sqrtPriceX96:     SQRT_PRICE_1_1,
                hookSalt:         keccak256("bBEU")
            })
        );
        console.log("bBEU Hook:  ", hookAddr);
        console.log("bBEU Token: ", tokenAddr);

        // ── Seed backing into the hook (150 index units worth) ──────────
        MockERC20(wbtcAddr).transfer(hookAddr, 150 * AMOUNTS_WBTC);
        MockERC20(wethAddr).transfer(hookAddr, 150 * AMOUNTS_WETH);
        wuniMock.transfer(hookAddr, 150 * AMOUNTS_WUNI);
        console.log("Backing transferred to hook.");

        // ── Write deploy2.json ──────────────────────────────────────────
        string memory j = "deploy2";
        vm.serializeAddress(j, "bundlHookAddress",  hookAddr);
        vm.serializeAddress(j, "bundlTokenAddress", tokenAddr);
        string memory out = vm.serializeAddress(j, "wuniAddress", wuniAddr);
        vm.writeJson(out, string.concat(vm.projectRoot(), "/deploy2.json"));
        console.log("deploy2.json written.");

        vm.stopBroadcast();
    }

    function _sort(address a, address b) internal pure returns (Currency, Currency) {
        return a < b
            ? (Currency.wrap(a), Currency.wrap(b))
            : (Currency.wrap(b), Currency.wrap(a));
    }
}
