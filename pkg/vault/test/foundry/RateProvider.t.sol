// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { VaultContractsDeployer } from "./utils/VaultContractsDeployer.sol";

contract RateProviderTest is VaultContractsDeployer {
    RateProviderMock rateProvider;

    function setUp() public {
        rateProvider = deployRateProviderMock();
    }

    function testRate__Fuzz(uint256 rate) public {
        rate = bound(rate, 1, 100e18);

        rateProvider.mockRate(rate);

        assertEq(rateProvider.getRate(), rate);
    }
}
