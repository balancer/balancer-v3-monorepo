// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BalancerPoolToken } from "../../contracts/BalancerPoolToken.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract FungibilityTest is BaseVaultTest {
    using FixedPoint for uint256;

    function setUp() public override {
        super.setUp();

        // Sets swap fee to 0, so we measure the real amount of minted BPTs.
        vault.manuallySetSwapFee(pool, 0);
    }

    function testFungibilityAddUnbalanced__Fuzz(uint256 proportion) public {
        proportion = bound(proportion, 1e12, 2e18);

        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(pool);

        uint256[] memory exactAmountsInUnbalanced = new uint256[](balancesRaw.length);
        uint256[] memory maxAmountsIn = new uint256[](balancesRaw.length);
        for (uint256 i = 0; i < balancesRaw.length; i++) {
            exactAmountsInUnbalanced[i] = balancesRaw[i].mulDown(proportion);
            maxAmountsIn[i] = MAX_UINT128;
        }

        uint256 totalSupplyBefore = BalancerPoolToken(pool).totalSupply();
        uint256 exactBptOutProportional = totalSupplyBefore.mulDown(proportion);

        uint256 snapshotId = vm.snapshot();
        vm.prank(lp);
        uint256 bptAmountOutUnbalanced = router.addLiquidityUnbalanced(
            pool,
            exactAmountsInUnbalanced,
            0,
            false,
            bytes("")
        );
        vm.revertTo(snapshotId);

        vm.prank(lp);
        uint256[] memory exactAmountsInProportional = router.addLiquidityProportional(
            pool,
            maxAmountsIn,
            exactBptOutProportional,
            false,
            bytes("")
        );

        // Ensure minted BPT is within 0.0001% of what it ideally should be.
        assertGe(exactBptOutProportional, bptAmountOutUnbalanced, "BPT unbalanced is bigger than proportional");
        assertApproxEqRel(exactBptOutProportional, bptAmountOutUnbalanced, 1e12, "BPT out is wrong");

        for (uint i = 0; i < balancesRaw.length; i++) {
            assertLe(
                exactAmountsInProportional[i],
                exactAmountsInUnbalanced[i],
                "Unbalanced amount in is smaller than proportional"
            );
        }
    }
}
