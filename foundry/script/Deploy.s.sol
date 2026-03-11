// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {BundlFactory} from "../src/BundlFactory.sol";
import {BundlHook} from "../src/BundlHook.sol";
import {BundlToken} from "../src/BundlToken.sol";

contract DeployScript is Script {
    using PoolIdLibrary for PoolKey;

    IPoolManager manager;
    PoolSwapTest swapRouter;
    PoolModifyLiquidityTest modifyLiqRouter;

    address usdc;
    address wbtc;
    address weth;

    address constant SEPOLIA_POOL_MANAGER      = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address constant SEPOLIA_MODIFY_LIQ_ROUTER = 0x0C478023803a644c94c4CE1C1e7b9A087e411B0A;
    address constant SEPOLIA_SWAP_ROUTER       = 0x9B6b46e2c869aa39918Db7f52f5557FE577B6eEe;

    uint8 constant USDC_DECIMALS = 6;

    // -------------------------------------------------------------------------
    // sqrtPriceX96 = sqrt(currency1_raw / currency0_raw) * 2^96
    //
    // WBTC pool — 1 WBTC ($85,000) priced in USDC
    //   usdcIs0 = true  → c0=USDC(6dec), c1=WBTC(8dec)
    //     ratio = 1e8 / (85000 * 1e6) = 1/850  → sqrt(1/850)*2^96
    //   usdcIs0 = false → c0=WBTC(8dec), c1=USDC(6dec)
    //     ratio = 85000 * 1e6 / 1e8 = 850      → sqrt(850)*2^96
    uint160 constant SQRT_PRICE_WBTC_USDC_IS0   = 2717503554927417600000000000;   // c0=USDC c1=WBTC
    uint160 constant SQRT_PRICE_WBTC_USDC_IS1   = 2309878021688305200000000000000; // c0=WBTC c1=USDC

    // WETH pool — 1 WETH ($2,000) priced in USDC
    //   usdcIs0 = true  → c0=USDC(6dec), c1=WETH(18dec)
    //     ratio = 1e18 / (2000 * 1e6) = 5e8    → sqrt(5e8)*2^96
    //   usdcIs0 = false → c0=WETH(18dec), c1=USDC(6dec)
    //     ratio = 2000 * 1e6 / 1e18 = 2e-9     → sqrt(2e-9)*2^96
    uint160 constant SQRT_PRICE_WETH_USDC_IS0   = 1771595571142957200000000000000000; // c0=USDC c1=WETH
    uint160 constant SQRT_PRICE_WETH_USDC_IS1   = 3543191142285914300000000;          // c0=WETH c1=USDC

    // Index token pool: start at 1:1 (price discovery happens via NAV swaps)
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    // -------------------------------------------------------------------------
    // amountsPerUnit: 1 index unit = ~$100 NAV (50% WBTC + 50% WETH)
    //   WBTC: $50 / $85000 * 1e8 = 58823 WBTC_wei
    //   WETH: $50 / $2000  * 1e18 = 25000000000000000 WETH_wei (2.5e16)
    uint256 constant AMOUNTS_WBTC = 58823;          // ~$50 at $85k/BTC
    uint256 constant AMOUNTS_WETH = 25_000_000_000_000_000; // ~$50 at $2k/ETH

    // -------------------------------------------------------------------------
    // Liquidity: ~$500k each side so a $1k swap causes visible price/NAV movement
    //   WBTC pool: 5.88 WBTC + 500k USDC  → L ≈ 17.1e9
    //   WETH pool: 250 WETH  + 500k USDC  → L ≈ 11.2e15
    int256 constant LIQ_WBTC_POOL = 17_149_858_512;
    int256 constant LIQ_WETH_POOL = 11_180_339_887_498_948;

    uint160 constant REQUIRED_FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
    );

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Starting deployment on chainId:", block.chainid);
        console.log("Deployer:", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        if (block.chainid == 31337) {
            console.log("=== Local Anvil Network Detected ===");
            manager = new PoolManager(deployerAddress);
            swapRouter = new PoolSwapTest(manager);
            modifyLiqRouter = new PoolModifyLiquidityTest(manager);

            MockERC20 usdcMock = new MockERC20("USD Coin", "USDC", USDC_DECIMALS);
            MockERC20 wbtcMock = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
            MockERC20 wethMock = new MockERC20("Wrapped Ether", "WETH", 18);
            usdc = address(usdcMock);
            wbtc = address(wbtcMock);
            weth = address(wethMock);

            // Mint realistic amounts
            usdcMock.mint(deployerAddress, 10_000_000e6);  // 10M USDC
            wbtcMock.mint(deployerAddress, 100e8);         // 100 WBTC
            wethMock.mint(deployerAddress, 10_000e18);     // 10k WETH

        } else if (block.chainid == 11155111) {
            console.log("=== Sepolia Testnet Detected ===");
            manager = IPoolManager(SEPOLIA_POOL_MANAGER);
            swapRouter = PoolSwapTest(SEPOLIA_SWAP_ROUTER);
            modifyLiqRouter = PoolModifyLiquidityTest(SEPOLIA_MODIFY_LIQ_ROUTER);

            MockERC20 usdcMock = new MockERC20("Mock USD Coin", "USDC", USDC_DECIMALS);
            MockERC20 wbtcMock = new MockERC20("Mock Wrapped Bitcoin", "WBTC", 8);
            MockERC20 wethMock = new MockERC20("Mock Wrapped Ether", "WETH", 18);
            usdcMock.mint(deployerAddress, 10_000_000e6);
            wbtcMock.mint(deployerAddress, 100e8);
            wethMock.mint(deployerAddress, 10_000e18);
            usdc = address(usdcMock);
            wbtc = address(wbtcMock);
            weth = address(wethMock);
        } else {
            revert("Unsupported Network");
        }

        console.log("Deploying BundlFactory...");
        BundlFactory factory = new BundlFactory(manager, usdc, USDC_DECIMALS);
        console.log("BundlFactory deployed at:", address(factory));

        // --- Build underlying pools ---
        PoolKey[] memory pKeys = new PoolKey[](2);
        bool[]    memory usdcIs0 = new bool[](2);

        // WBTC/USDC pool
        (Currency c0, Currency c1) = _sortCurrencies(wbtc, usdc);
        pKeys[0] = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))});
        usdcIs0[0] = Currency.unwrap(c0) == usdc;
        uint160 wbtcSqrtPrice = usdcIs0[0] ? SQRT_PRICE_WBTC_USDC_IS0 : SQRT_PRICE_WBTC_USDC_IS1;
        manager.initialize(pKeys[0], wbtcSqrtPrice);

        // WETH/USDC pool
        (c0, c1) = _sortCurrencies(weth, usdc);
        pKeys[1] = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))});
        usdcIs0[1] = Currency.unwrap(c0) == usdc;
        uint160 wethSqrtPrice = usdcIs0[1] ? SQRT_PRICE_WETH_USDC_IS0 : SQRT_PRICE_WETH_USDC_IS1;
        manager.initialize(pKeys[1], wethSqrtPrice);

        // --- Add liquidity (~$500k per pool) ---
        console.log("Adding liquidity to underlying pools...");
        MockERC20(usdc).approve(address(modifyLiqRouter), type(uint256).max);
        MockERC20(wbtc).approve(address(modifyLiqRouter), type(uint256).max);
        MockERC20(weth).approve(address(modifyLiqRouter), type(uint256).max);

        modifyLiqRouter.modifyLiquidity(
            pKeys[0],
            IPoolManager.ModifyLiquidityParams({
                tickLower: -887220,
                tickUpper:  887220,
                liquidityDelta: LIQ_WBTC_POOL,
                salt: 0
            }),
            ""
        );
        modifyLiqRouter.modifyLiquidity(
            pKeys[1],
            IPoolManager.ModifyLiquidityParams({
                tickLower: -887220,
                tickUpper:  887220,
                liquidityDelta: LIQ_WETH_POOL,
                salt: 0
            }),
            ""
        );
        console.log("Liquidity added.");

        // --- Build index params ---
        address[] memory uTokens = new address[](2);
        uTokens[0] = wbtc;
        uTokens[1] = weth;

        uint256[] memory amountsPerUnit = new uint256[](2);
        amountsPerUnit[0] = AMOUNTS_WBTC; // 58823 WBTC_wei  (~$50 at $85k/BTC)
        amountsPerUnit[1] = AMOUNTS_WETH; // 2.5e16 WETH_wei (~$50 at $2k/ETH)

        uint256[] memory weightsBps = new uint256[](2);
        weightsBps[0] = 5000; // 50% WBTC
        weightsBps[1] = 5000; // 50% WETH

        uint8[] memory tokenDecimals = new uint8[](2);
        tokenDecimals[0] = 8;
        tokenDecimals[1] = 18;

        console.log("Deploying Bundl index (Token + Hook + Pool)...");
        (address hook, address token, PoolId idxPoolId) = factory.createBundl(
            BundlFactory.CreateBundlParams({
                name:             "Blue Chip DeFi",
                symbol:           "bBLUE",
                underlyingTokens: uTokens,
                amountsPerUnit:   amountsPerUnit,
                weightsBps:       weightsBps,
                underlyingPools:  pKeys,
                usdcIs0:          usdcIs0,
                tokenDecimals:    tokenDecimals,
                sqrtPriceX96:     SQRT_PRICE_1_1
            })
        );

        // Seed the hook vault with initial backing
        // 150 units * amountsPerUnit to allow early sells/redeems
        MockERC20(wbtc).transfer(hook, 150 * AMOUNTS_WBTC);  // ~$750k WBTC
        MockERC20(weth).transfer(hook, 150 * AMOUNTS_WETH);  // ~$750k WETH

        console.log("--- Deployments ---");
        console.log("USDC:         ", usdc);
        console.log("WBTC:         ", wbtc);
        console.log("WETH:         ", weth);
        console.log("PoolManager:  ", address(manager));
        console.log("BundlFactory: ", address(factory));
        console.log("BundlHook:    ", hook);
        console.log("BundlToken:   ", token);
        console.log("NAV per unit ~$100 (50% WBTC + 50% WETH)");
        console.log("Pool liquidity: ~$500k per underlying pool");

        string memory jsonObj = "deployments";
        vm.serializeAddress(jsonObj, "usdcAddress",                usdc);
        vm.serializeAddress(jsonObj, "wbtcAddress",                wbtc);
        vm.serializeAddress(jsonObj, "wethAddress",                weth);
        vm.serializeAddress(jsonObj, "poolManagerAddress",         address(manager));
        vm.serializeAddress(jsonObj, "swapRouterAddress",          address(swapRouter));
        vm.serializeAddress(jsonObj, "modifyLiquidityRouterAddress", address(modifyLiqRouter));
        vm.serializeAddress(jsonObj, "bundlFactoryAddress",        address(factory));
        vm.serializeAddress(jsonObj, "bundlHookAddress",           hook);
        string memory finalJson = vm.serializeAddress(jsonObj, "bundlTokenAddress", token);
        vm.writeJson(finalJson, string.concat(vm.projectRoot(), "/deploy.json"));

        vm.stopBroadcast();
    }

    function _sortCurrencies(address a, address b) internal pure returns (Currency, Currency) {
        return a < b ? (Currency.wrap(a), Currency.wrap(b)) : (Currency.wrap(b), Currency.wrap(a));
    }
}
