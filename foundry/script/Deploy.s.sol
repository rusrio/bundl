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

    uint8   constant USDC_DECIMALS   = 6;
    uint160 constant SQRT_PRICE_1_1  = 79228162514264337593543950336;

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
            usdcMock.mint(deployerAddress, 100_000_000e6);
            wbtcMock.mint(deployerAddress, 100e8);
            wethMock.mint(deployerAddress, 1_000e18);

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

        (Currency c0, Currency c1) = _sortCurrencies(wbtc, usdc);
        pKeys[0] = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))});
        manager.initialize(pKeys[0], SQRT_PRICE_1_1);
        usdcIs0[0] = Currency.unwrap(c0) == usdc;

        (c0, c1) = _sortCurrencies(weth, usdc);
        pKeys[1] = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))});
        manager.initialize(pKeys[1], SQRT_PRICE_1_1);
        usdcIs0[1] = Currency.unwrap(c0) == usdc;

        // Add liquidity
        console.log("Adding mock liquidity to underlying pools...");
        MockERC20(usdc).mint(deployerAddress, 1_000_000_000e18);
        MockERC20(wbtc).mint(deployerAddress, 1_000_000_000e18);
        MockERC20(weth).mint(deployerAddress, 1_000_000_000e18);
        MockERC20(usdc).approve(address(modifyLiqRouter), type(uint256).max);
        MockERC20(wbtc).approve(address(modifyLiqRouter), type(uint256).max);
        MockERC20(weth).approve(address(modifyLiqRouter), type(uint256).max);
        modifyLiqRouter.modifyLiquidity(
            pKeys[0],
            IPoolManager.ModifyLiquidityParams({tickLower: -887220, tickUpper: 887220, liquidityDelta: 50_000_000e18, salt: 0}),
            ""
        );
        modifyLiqRouter.modifyLiquidity(
            pKeys[1],
            IPoolManager.ModifyLiquidityParams({tickLower: -887220, tickUpper: 887220, liquidityDelta: 50_000_000e18, salt: 0}),
            ""
        );
        console.log("Liquidity added.");

        // --- Build index params ---
        address[] memory uTokens = new address[](2);
        uTokens[0] = wbtc;
        uTokens[1] = weth;

        uint256[] memory amountsPerUnit = new uint256[](2);
        amountsPerUnit[0] = 1e5;
        amountsPerUnit[1] = 1e5;

        uint256[] memory weightsBps = new uint256[](2);
        weightsBps[0] = 5000;
        weightsBps[1] = 5000;

        uint8[] memory tokenDecimals = new uint8[](2);
        tokenDecimals[0] = 8;
        tokenDecimals[1] = 18;

        console.log("Deploying Bundl (Token + Hook)...");
        (address hook, address token, PoolId idxPoolId) = factory.createBundl(
            BundlFactory.CreateBundlParams({
                name: "Blue Chip DeFi",
                symbol: "bBLUE",
                underlyingTokens: uTokens,
                amountsPerUnit: amountsPerUnit,
                weightsBps: weightsBps,
                underlyingPools: pKeys,
                usdcIs0: usdcIs0,
                tokenDecimals: tokenDecimals,
                sqrtPriceX96: SQRT_PRICE_1_1
            })
        );

        console.log("--- Deployments ---");
        console.log("USDC:",         usdc);
        console.log("WBTC:",         wbtc);
        console.log("WETH:",         weth);
        console.log("PoolManager:",  address(manager));
        console.log("BundlFactory:", address(factory));
        console.log("BundlHook:",    hook);
        console.log("BundlToken:",   token);

        MockERC20(wbtc).transfer(hook, 10e8);
        MockERC20(weth).transfer(hook, 500e18);

        string memory jsonObj = "deployments";
        vm.serializeAddress(jsonObj, "usdcAddress", usdc);
        vm.serializeAddress(jsonObj, "wbtcAddress", wbtc);
        vm.serializeAddress(jsonObj, "wethAddress", weth);
        vm.serializeAddress(jsonObj, "poolManagerAddress", address(manager));
        vm.serializeAddress(jsonObj, "swapRouterAddress", address(swapRouter));
        vm.serializeAddress(jsonObj, "modifyLiquidityRouterAddress", address(modifyLiqRouter));
        vm.serializeAddress(jsonObj, "bundlFactoryAddress", address(factory));
        vm.serializeAddress(jsonObj, "bundlHookAddress", hook);
        string memory finalJson = vm.serializeAddress(jsonObj, "bundlTokenAddress", token);
        vm.writeJson(finalJson, string.concat(vm.projectRoot(), "/deploy.json"));

        vm.stopBroadcast();
    }

    function _mineSalt(bytes memory creationCode, uint160 flags, address factory) internal pure returns (bytes32 salt) {
        bytes32 initCodeHash = keccak256(creationCode);
        for (uint256 i = 0; i < type(uint256).max; i++) {
            salt = bytes32(i);
            address predicted = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), factory, salt, initCodeHash))))
            );
            if (uint160(predicted) & Hooks.ALL_HOOK_MASK == flags) return salt;
        }
        revert("SaltMiningFailed");
    }

    function _sortCurrencies(address a, address b) internal pure returns (Currency, Currency) {
        return a < b ? (Currency.wrap(a), Currency.wrap(b)) : (Currency.wrap(b), Currency.wrap(a));
    }
}
