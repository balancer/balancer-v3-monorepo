// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BalancerPoolToken } from "../../contracts/BalancerPoolToken.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract FungibilityTest is BaseVaultTest {
    using FixedPoint for uint256;

    function testFungibilityAddUnbalanced__Fuzz(uint256 proportion) public {
        proportion = bound(proportion, 1e12, 2e18);

        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(pool);

        uint256[] memory exactAmountsIn = new uint256[](balancesRaw.length);
        for (uint256 i = 0; i < balancesRaw.length; i++) {
            exactAmountsIn[i] = balancesRaw[i].mulDown(proportion);
        }

        uint256 totalSupplyBefore = BalancerPoolToken(pool).totalSupply();

        vm.prank(lp);
        uint256 bptAmountOut = router.addLiquidityUnbalanced(pool, exactAmountsIn, 0, false, bytes(""));

        // Ensure minted BPT is within 0.0001% of what it ideally should be.
        assertApproxEqRel(totalSupplyBefore.mulDown(proportion), bptAmountOut, 1e12, "BPT out is wrong");
    }
}
