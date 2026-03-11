// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract DebugSwap is Script {
    using CurrencyLibrary for Currency;

    function run() public {
        vm.startBroadcast();

        address usdc;
        address poolManager;
        
        string memory deployJson = vm.readFile(string.concat(vm.projectRoot(), "/deploy.json"));
        usdc = vm.parseJsonAddress(deployJson, ".usdcAddress");
        poolManager = vm.parseJsonAddress(deployJson, ".poolManagerAddress");
        address hookAddress = vm.parseJsonAddress(deployJson, ".bundlHookAddress");
        address indexToken = vm.parseJsonAddress(deployJson, ".bundlTokenAddress");
        address router = vm.parseJsonAddress(deployJson, ".swapRouterAddress");

        console2.log("USDC: ", usdc);
        console2.log("Manager: ", poolManager);
        console2.log("Hook: ", hookAddress);
        console2.log("Router: ", router);

        address currency0 = usdc < indexToken ? usdc : indexToken;
        address currency1 = usdc < indexToken ? indexToken : usdc;

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hookAddress)
        });

        // 10 USDC
        uint256 amountIn = 10 * 1e6; 

        // Mint instead of having to deal
        MockERC20(usdc).mint(msg.sender, amountIn);

        // Approve router
        IERC20(usdc).approve(router, type(uint256).max);

        bool zeroForOne = (usdc == currency0);
        
        // Exact input (-10e6)
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn),
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        console2.log("Executing swap...");
        PoolSwapTest(router).swap(
            poolKey,
            swapParams,
            testSettings,
            ""
        );
        console2.log("Swap completed!");

        vm.stopBroadcast();
    }
}
