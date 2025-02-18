// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

contract CowAclAmmTest is BaseVaultTest {
    function setUp() public override {
        super.setUp();
        pool = new CowAclAmm(
            WeightedPool.NewPoolParams({
                name: "Test Pool",
                symbol: "TEST",
                numTokens: 2,
                normalizedWeights: [1e18, 1e18],
                version: "1.0"
            }),
            vault,
            address(router),
            1.4e18, // PriceRange = 4 (Example ETH/USDC 1000 - 4000)
            10e16, // Margin 10%
            100e16 // Increase per day 100%
        );
    }

    // function testAclAmm() public {

    // }
}
