// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";

contract RoundingDirectionStablePoolTest is Test {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    function testComputeInvariantRatioRounding(
        uint256 currentAmp,
        uint256[3] memory currentBalances,
        uint256[3] memory amountsIn
    ) public view {
        currentAmp = bound(currentAmp, 100, 1000);
        currentBalances[0] = bound(currentBalances[0], 1000e18, 1_000_000e18);
        currentBalances[1] = bound(currentBalances[1], 1000e18, 1_000_000e18);
        currentBalances[2] = bound(currentBalances[2], 1000e18, 1_000_000e18);
        amountsIn[0] = bound(amountsIn[0], 0.1e18, 100_000e18);
        amountsIn[1] = bound(amountsIn[1], 0.1e18, 100_000e18);
        amountsIn[2] = bound(amountsIn[2], 0.1e18, 100_000e18);

        uint256[] memory newBalances = new uint256[](3);
        newBalances[0] = currentBalances[0] + amountsIn[0];
        newBalances[1] = currentBalances[0] + amountsIn[1];
        newBalances[2] = currentBalances[0] + amountsIn[2];

        uint256[] memory newBalancesRoundDown = new uint256[](3);
        newBalancesRoundDown[0] = newBalances[0] - 1;
        newBalancesRoundDown[1] = newBalances[1] - 1;
        newBalancesRoundDown[2] = newBalances[2] - 1;

        // Check that the invariant converges in every case.
        try this.computeInvariant(currentAmp, currentBalances.toMemoryArray(), Rounding.ROUND_DOWN) returns (
            uint256
        ) {} catch {
            vm.assume(false);
        }

        try this.computeInvariant(currentAmp, newBalances, Rounding.ROUND_UP) returns (uint256) {} catch {
            vm.assume(false);
        }

        try this.computeInvariant(currentAmp, newBalancesRoundDown, Rounding.ROUND_UP) returns (uint256) {} catch {
            vm.assume(false);
        }

        // Base case: use same rounding for balances in numerator and denominator, and use same rounding direction
        // for `computeInvariant` calls (which is accurate to 1 wei in stable math).
        uint256 currentInvariant = computeInvariant(currentAmp, currentBalances.toMemoryArray(), Rounding.ROUND_DOWN);
        uint256 invariantRatioRegular = computeInvariant(currentAmp, newBalances, Rounding.ROUND_DOWN).divDown(
            currentInvariant
        );

        // Improved rounding down: use balances rounded down in numerator, and use rounding direction when calling
        // `computeInvariant` (1 wei difference).
        uint256 currentInvariantUp = computeInvariant(currentAmp, currentBalances.toMemoryArray(), Rounding.ROUND_UP);
        uint256 invariantRatioDown = computeInvariant(currentAmp, newBalancesRoundDown, Rounding.ROUND_DOWN).divDown(
            currentInvariantUp
        );

        assertLe(invariantRatioDown, invariantRatioRegular, "Invariant ratio should have gone down");
    }

    function computeInvariant(
        uint256 currentAmp,
        uint256[] memory balancesLiveScaled18,
        Rounding rounding
    ) public pure returns (uint256) {
        uint256 invariant = StableMath.computeInvariant(currentAmp, balancesLiveScaled18);
        if (invariant > 0) {
            invariant = rounding == Rounding.ROUND_DOWN ? invariant : invariant + 1;
        }

        return invariant;
    }
}
