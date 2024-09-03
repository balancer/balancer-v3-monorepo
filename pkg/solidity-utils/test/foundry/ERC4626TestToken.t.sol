// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { BaseTest } from "./utils/BaseTest.sol";
import { ERC4626TestToken } from "../../contracts/test/ERC4626TestToken.sol";

contract ERC4626TestTokenTest is BaseTest {
    ERC4626TestToken internal wToken;
    uint256 internal constant WRAPPER_INITIAL_AMOUNT = 1e3 * 1e18;

    function setUp() public override {
        super.setUp();
        wToken = new ERC4626TestToken(dai, "wDai", "wDai", 18);
        vm.label(address(wToken), "wToken");
        // Initializes the wrapped token with a rate of 1.
        wToken.inflateUnderlyingOrWrapped(WRAPPER_INITIAL_AMOUNT, WRAPPER_INITIAL_AMOUNT);
    }

    function testMockRateIncrease() public {
        wToken.mockRate(2e18);
        assertEq(wToken.totalAssets(), 2 * WRAPPER_INITIAL_AMOUNT, "Wrong total assets for rate 2");
        assertEq(wToken.totalSupply(), WRAPPER_INITIAL_AMOUNT, "Wrong total supply for rate 2");
    }

    function testMockRateDecrease() public {
        wToken.mockRate(0.5e18);
        assertEq(wToken.totalAssets(), WRAPPER_INITIAL_AMOUNT, "Wrong total assets for rate 0.5");
        assertEq(wToken.totalSupply(), 2 * WRAPPER_INITIAL_AMOUNT, "Wrong total supply for rate 0.5");
    }

    function testMockRateIncreaseDecrease() public {
        wToken.mockRate(2e18);
        assertEq(wToken.totalAssets(), 2 * WRAPPER_INITIAL_AMOUNT, "Wrong total assets for rate 2");
        assertEq(wToken.totalSupply(), WRAPPER_INITIAL_AMOUNT, "Wrong total supply for rate 2");
        // getRate rounds the rate down, which removes 1 wei from the actual rate.
        assertApproxEqAbs(wToken.getRate(), 2e18, 1, "Wrong token rate for rate 2");

        wToken.mockRate(1.5e18);
        assertEq(wToken.totalAssets(), 2 * WRAPPER_INITIAL_AMOUNT, "Wrong total assets for rate 1.5");
        // To decrease the rate from 2 to 1.5, we need to mint more wrapped tokens, so that the rate between assets
        // and wrapped is 1.5. Since the wToken has 2 * WRAPPER_INITIAL_AMOUNT underlying, the amount of wrapped must
        // be `4 * WRAPPER_INITIAL_AMOUNT / 3`.
        assertEq(wToken.totalSupply(), (4 * WRAPPER_INITIAL_AMOUNT) / 3, "Wrong total supply for rate 1.5");
        // getRate rounds the rate down, which removes 1 wei from the actual rate.
        assertApproxEqAbs(wToken.getRate(), 1.5e18, 1, "Wrong token rate for rate 1.5");

        wToken.mockRate(0.5e18);
        assertEq(wToken.totalAssets(), 2 * WRAPPER_INITIAL_AMOUNT, "Wrong total assets for rate 0.5");
        assertEq(wToken.totalSupply(), 4 * WRAPPER_INITIAL_AMOUNT, "Wrong total supply for rate 0.5");
        // getRate rounds the rate down, which removes 1 wei from the actual rate.
        assertApproxEqAbs(wToken.getRate(), 0.5e18, 1, "Wrong token rate for rate 0.5");

        wToken.mockRate(4e18);
        assertEq(wToken.totalAssets(), 16 * WRAPPER_INITIAL_AMOUNT, "Wrong total assets for rate 4");
        assertEq(wToken.totalSupply(), 4 * WRAPPER_INITIAL_AMOUNT, "Wrong total supply for rate 4");
        // getRate rounds the rate down, which removes 1 wei from the actual rate.
        assertApproxEqAbs(wToken.getRate(), 4e18, 1, "Wrong token rate for rate 4");
    }
}
