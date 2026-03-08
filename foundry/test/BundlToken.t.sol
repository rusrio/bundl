// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {BundlToken} from "../src/BundlToken.sol";

contract BundlTokenTest is Test {
    BundlToken public token;
    address public minter = address(0xBEEF);
    address public user = address(0xCAFE);

    function setUp() public {
        token = new BundlToken("Bundl BTC-ETH", "bBTC-ETH", minter);
    }

    function test_nameAndSymbol() public view {
        assertEq(token.name(), "Bundl BTC-ETH");
        assertEq(token.symbol(), "bBTC-ETH");
        assertEq(token.decimals(), 18);
    }

    function test_minterIsCorrect() public view {
        assertEq(token.minter(), minter);
    }

    function test_mintByMinter() public {
        vm.prank(minter);
        token.mint(user, 100e18);
        assertEq(token.balanceOf(user), 100e18);
        assertEq(token.totalSupply(), 100e18);
    }

    function test_burnByMinter() public {
        vm.prank(minter);
        token.mint(user, 100e18);

        vm.prank(minter);
        token.burn(user, 40e18);
        assertEq(token.balanceOf(user), 60e18);
        assertEq(token.totalSupply(), 60e18);
    }

    function test_revertMintByNonMinter() public {
        vm.prank(user);
        vm.expectRevert(BundlToken.OnlyMinter.selector);
        token.mint(user, 100e18);
    }

    function test_revertBurnByNonMinter() public {
        vm.prank(minter);
        token.mint(user, 100e18);

        vm.prank(user);
        vm.expectRevert(BundlToken.OnlyMinter.selector);
        token.burn(user, 50e18);
    }

    function testFuzz_mintArbitraryAmount(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint128).max);
        vm.prank(minter);
        token.mint(user, amount);
        assertEq(token.balanceOf(user), amount);
    }
}
