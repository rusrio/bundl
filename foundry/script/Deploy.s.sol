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
import {BundlRouter} from "../src/BundlRouter.sol";

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

    uint160 constant SQRT_PRICE_WBTC_USDC_IS0   = 2717503554927417600000000000;
    uint160 constant SQRT_PRICE_WBTC_USDC_IS1   = 2309878021688305200000000000000;
    uint160 constant SQRT_PRICE_WETH_USDC_IS0   = 1771595571142957200000000000000000;
    uint160 constant SQRT_PRICE_WETH_USDC_IS1   = 3543191142285914300000000;
    uint160 constant SQRT_PRICE_1_1             = 79228162514264337593543950336;

    uint256 constant AMOUNTS_WBTC = 58823;
    uint256 constant AMOUNTS_WETH = 25_000_000_000_000_000;

    int256 constant LIQ_WBTC_POOL = 17_149_858_512;
    int256 constant LIQ_WETH_POOL = 11_180_339_887_498_948;

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
            MockERC20 wethMock = new MockERC20("Mock Wrapped Ether", "WETH", 18);
            usdc = address(usdcMock);
            wbtc = address(wbtcMock);
            weth = address(wethMock);
            usdcMock.mint(deployerAddress, 10_000_000e6);
            wbtcMock.mint(deployerAddress, 100e8);
            wethMock.mint(deployerAddress, 10_000e18);

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

        // Deploy BundlFactory + BundlRouter once (shared across all indices)
        console.log("Deploying BundlFactory...");
        BundlFactory factory = new BundlFactory(manager, usdc, USDC_DECIMALS);
        console.log("BundlFactory deployed at:", address(factory));

        console.log("Deploying BundlRouter (generic, shared)...");
        BundlRouter bundlRouter = new BundlRouter(manager);
        console.log("BundlRouter deployed at:", address(bundlRouter));

        // --- Build underlying pools ---
        PoolKey[] memory pKeys = new PoolKey[](2);
        bool[]    memory usdcIs0 = new bool[](2);

        (Currency c0, Currency c1) = _sortCurrencies(wbtc, usdc);
        pKeys[0] = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))});
        usdcIs0[0] = Currency.unwrap(c0) == usdc;
        manager.initialize(pKeys[0], usdcIs0[0] ? SQRT_PRICE_WBTC_USDC_IS0 : SQRT_PRICE_WBTC_USDC_IS1);

        (c0, c1) = _sortCurrencies(weth, usdc);
        pKeys[1] = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))});
        usdcIs0[1] = Currency.unwrap(c0) == usdc;
        manager.initialize(pKeys[1], usdcIs0[1] ? SQRT_PRICE_WETH_USDC_IS0 : SQRT_PRICE_WETH_USDC_IS1);

        console.log("Adding liquidity to underlying pools...");
        MockERC20(usdc).approve(address(modifyLiqRouter), type(uint256).max);
        MockERC20(wbtc).approve(address(modifyLiqRouter), type(uint256).max);
        MockERC20(weth).approve(address(modifyLiqRouter), type(uint256).max);
        modifyLiqRouter.modifyLiquidity(pKeys[0], IPoolManager.ModifyLiquidityParams({tickLower: -887220, tickUpper: 887220, liquidityDelta: LIQ_WBTC_POOL, salt: 0}), "");
        modifyLiqRouter.modifyLiquidity(pKeys[1], IPoolManager.ModifyLiquidityParams({tickLower: -887220, tickUpper: 887220, liquidityDelta: LIQ_WETH_POOL, salt: 0}), "");
        console.log("Liquidity added.");

        address[] memory uTokens      = new address[](2);
        uint256[] memory amountsPerUnit = new uint256[](2);
        uint256[] memory weightsBps   = new uint256[](2);
        uint8[]   memory tokenDecimals = new uint8[](2);
        uTokens[0] = wbtc;        uTokens[1] = weth;
        amountsPerUnit[0] = AMOUNTS_WBTC; amountsPerUnit[1] = AMOUNTS_WETH;
        weightsBps[0] = 5000;     weightsBps[1] = 5000;
        tokenDecimals[0] = 8;     tokenDecimals[1] = 18;

        console.log("Deploying Bundl index (Token + Hook + Pool)...");
        (address hookAddr, address token,) = factory.createBundl(
            BundlFactory.CreateBundlParams({
                name:             "Blue Chip DeFi",
                symbol:           "bBLUE",
                underlyingTokens: uTokens,
                amountsPerUnit:   amountsPerUnit,
                weightsBps:       weightsBps,
                underlyingPools:  pKeys,
                usdcIs0:          usdcIs0,
                tokenDecimals:    tokenDecimals,
                sqrtPriceX96:     SQRT_PRICE_1_1,
                hookSalt:         keccak256("bBLUE")
            })
        );

        MockERC20(wbtc).transfer(hookAddr, 150 * AMOUNTS_WBTC);
        MockERC20(weth).transfer(hookAddr, 150 * AMOUNTS_WETH);

        console.log("--- Deployments ---");
        console.log("USDC:         ", usdc);
        console.log("WBTC:         ", wbtc);
        console.log("WETH:         ", weth);
        console.log("PoolManager:  ", address(manager));
        console.log("BundlFactory: ", address(factory));
        console.log("BundlRouter:  ", address(bundlRouter));
        console.log("BundlHook:    ", hookAddr);
        console.log("BundlToken:   ", token);

        string memory jsonObj = "deployments";
        vm.serializeAddress(jsonObj, "usdcAddress",                  usdc);
        vm.serializeAddress(jsonObj, "wbtcAddress",                  wbtc);
        vm.serializeAddress(jsonObj, "wethAddress",                  weth);
        vm.serializeAddress(jsonObj, "poolManagerAddress",           address(manager));
        vm.serializeAddress(jsonObj, "swapRouterAddress",            address(swapRouter));
        vm.serializeAddress(jsonObj, "modifyLiquidityRouterAddress", address(modifyLiqRouter));
        vm.serializeAddress(jsonObj, "bundlFactoryAddress",          address(factory));
        vm.serializeAddress(jsonObj, "bundlRouterAddress",           address(bundlRouter));
        vm.serializeAddress(jsonObj, "bundlHookAddress",             hookAddr);
        string memory finalJson = vm.serializeAddress(jsonObj, "bundlTokenAddress", token);
        vm.writeJson(finalJson, string.concat(vm.projectRoot(), "/deploy.json"));

        vm.stopBroadcast();
    }

    function _sortCurrencies(address a, address b) internal pure returns (Currency, Currency) {
        return a < b ? (Currency.wrap(a), Currency.wrap(b)) : (Currency.wrap(b), Currency.wrap(a));
    }
}
