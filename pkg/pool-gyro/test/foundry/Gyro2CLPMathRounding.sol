// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import "../../contracts/lib/Gyro2CLPMath.sol";

struct QuadraticTerms {
    uint256 a;
    uint256 mb;
    uint256 bSquare;
    uint256 mc;
}

contract Gyro2CLPMathRoundingTest is Test {
    using ArrayHelpers for *;

    uint256 internal constant MIN_DIFF_ALPHA_BETA = 1e14;

    uint256 internal constant MIN_SQRT_ALPHA = 0.8e18;
    uint256 internal constant MAX_SQRT_ALPHA = 1.2e18 - MIN_DIFF_ALPHA_BETA;
    // Make sqrtBeta 0.5% higher than sqrtAlpha
    uint256 internal constant MIN_SQRT_BETA = MIN_SQRT_ALPHA;
    uint256 internal constant MAX_SQRT_BETA = MAX_SQRT_ALPHA + MIN_DIFF_ALPHA_BETA;

    function testCalculateQuadraticTermsRounding__Fuzz(
        uint256[2] memory balances,
        uint256 sqrtAlpha,
        uint256 sqrtBeta
    ) public pure {
        balances[0] = bound(balances[0], 1e16, 1e8 * 1e18);
        balances[1] = bound(balances[1], 1e16, 1e8 * 1e18);
        sqrtAlpha = bound(sqrtAlpha, MIN_SQRT_ALPHA, MAX_SQRT_ALPHA);
        sqrtBeta = bound(sqrtBeta, sqrtAlpha + MIN_DIFF_ALPHA_BETA, MAX_SQRT_BETA);

        QuadraticTerms memory qTermsDown;
        QuadraticTerms memory qTermsUp;

        (qTermsDown.a, qTermsDown.mb, qTermsDown.bSquare, qTermsDown.mc) = Gyro2CLPMath.calculateQuadraticTerms(
            balances.toMemoryArray(),
            sqrtAlpha,
            sqrtBeta,
            Rounding.ROUND_DOWN
        );
        (qTermsUp.a, qTermsUp.mb, qTermsUp.bSquare, qTermsUp.mc) = Gyro2CLPMath.calculateQuadraticTerms(
            balances.toMemoryArray(),
            sqrtAlpha,
            sqrtBeta,
            Rounding.ROUND_UP
        );

        assertLe(qTermsUp.a, qTermsDown.a, "Wrong rounding result (a)");
        assertGe(qTermsUp.mb, qTermsDown.mb, "Wrong rounding result (mb)");
        assertGe(qTermsUp.bSquare, qTermsDown.bSquare, "Wrong rounding result (bSquare)");
        assertGe(qTermsUp.mc, qTermsDown.mc, "Wrong rounding result (mc)");
    }

    function testCalculateQuadraticRounding__Fuzz(uint256 a, uint256 mb, uint256 mc) public pure {
        a = bound(a, 1, 1e18); // 0 < a < FP(1)
        mb = bound(mb, 1, 1e8 * 1e18);
        uint256 bSquare = mb * mb; // This is an approximation just to unit fuzz calculate quadratic.
        mc = bound(mc, 1, 1e8 * 1e18);

        uint256 quadraticRoundDown = Gyro2CLPMath.calculateQuadratic(a, mb, bSquare, mc, Rounding.ROUND_DOWN);
        uint256 quadraticRoundUp = Gyro2CLPMath.calculateQuadratic(a, mb, bSquare, mc, Rounding.ROUND_UP);

        assertGe(quadraticRoundUp, quadraticRoundDown, "Wrong rounding result");
    }

    function testComputeInvariantRounding__Fuzz(
        uint256[2] memory balances,
        uint256 sqrtAlpha,
        uint256 sqrtBeta
    ) public pure {
        balances[0] = bound(balances[0], 1e16, 1e8 * 1e18);
        balances[1] = bound(balances[1], 1e16, 1e8 * 1e18);
        sqrtAlpha = bound(sqrtAlpha, MIN_SQRT_ALPHA, MAX_SQRT_ALPHA);
        sqrtBeta = bound(sqrtBeta, sqrtAlpha + MIN_DIFF_ALPHA_BETA, MAX_SQRT_BETA);

        uint256 invariantDown = Gyro2CLPMath.calculateInvariant(
            balances.toMemoryArray(),
            sqrtAlpha,
            sqrtBeta,
            Rounding.ROUND_DOWN
        );
        uint256 invariantUp = Gyro2CLPMath.calculateInvariant(
            balances.toMemoryArray(),
            sqrtAlpha,
            sqrtBeta,
            Rounding.ROUND_UP
        );

        assertGe(invariantUp, invariantDown, "Wrong rounding result");
    }
}
