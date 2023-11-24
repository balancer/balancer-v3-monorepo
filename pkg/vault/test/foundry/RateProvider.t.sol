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

    function testRate(uint64 rate) public {
        vm.assume(rate <= 10e18);

        rateProvider.mockRate(rate);

        assertEq(rateProvider.getRate(), rate);
    }
}
