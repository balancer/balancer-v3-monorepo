// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";

contract RateProviderTest is Test {
    RateProviderMock rateProvider;

    function setUp() public {
        rateProvider = new RateProviderMock();
    }

    function testUnderlying(address token) public {
        rateProvider.setUnderlyingToken(IERC20(token));

        assertEq(address(rateProvider.getUnderlyingToken()), token);
    }

    function testRate(uint256 rate) public {
        rate = bound(rate, 1, 100e18);

        rateProvider.mockRate(rate);

        assertEq(rateProvider.getRate(), rate);
    }

    function testWrappedToken() public {
        // Flag is initialized to false
        assertFalse(rateProvider.isWrappedToken());

        // Can set to true
        rateProvider.setWrappedTokenFlag(true);
        assertTrue(rateProvider.isWrappedToken());

        // Can reset to false
        rateProvider.setWrappedTokenFlag(false);
        assertFalse(rateProvider.isWrappedToken());
    }

    function testYieldExemptToken() public {
        // Flag is initialized to false
        assertFalse(rateProvider.isExemptFromYieldProtocolFee());

        // Can set to true
        rateProvider.setYieldExemptFlag(true);
        assertTrue(rateProvider.isExemptFromYieldProtocolFee());

        // Can reset to false
        rateProvider.setYieldExemptFlag(false);
        assertFalse(rateProvider.isExemptFromYieldProtocolFee());
    }
}
