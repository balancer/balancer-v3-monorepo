// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";

contract CoverageStableMathZeroSumTest is Test {
    function testComputeInvariantReturnsZeroWhenSumIsZero() public pure {
        uint256[] memory balances = new uint256[](2);
        balances[0] = 0;
        balances[1] = 0;

        // Use a production-like scaled amp value.
        uint256 amp = 200 * StableMath.AMP_PRECISION;
        uint256 invariant = StableMath.computeInvariant(amp, balances);
        assertEq(invariant, 0);
    }
}

