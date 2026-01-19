// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { GyroECLPMath } from "../../contracts/lib/GyroECLPMath.sol";

contract GyroECLPMathCoverageTest is Test {
    function test_mulAinv_inverts_mulA_noRotation() public pure {
        IGyroECLPPool.EclpParams memory p;
        p.c = 1e18;
        p.s = 0;
        p.lambda = 2e18;

        IGyroECLPPool.Vector2 memory tp = IGyroECLPPool.Vector2(int256(123e18), int256(456e18));
        IGyroECLPPool.Vector2 memory t = GyroECLPMath.mulA(p, tp);
        IGyroECLPPool.Vector2 memory back = GyroECLPMath.mulAinv(p, t);

        assertEq(back.x, tp.x);
        assertEq(back.y, tp.y);
    }

    function test_tau_eta_zeta_smoke() public pure {
        // Hit tau/eta/zeta helpers (often only reached in “derived param” helper code).
        IGyroECLPPool.EclpParams memory p;
        // Minimal valid-ish params for mapping; values chosen to avoid divide-by-zero.
        p.alpha = int256(9e17);
        p.beta = int256(11e17);
        p.c = int256(1e18);
        p.s = int256(0);
        p.lambda = int256(1e18);

        IGyroECLPPool.Vector2 memory tpp = GyroECLPMath.tau(p, int256(1e18));
        // Non-zero y is the important sanity condition for downstream computations.
        assertTrue(tpp.y != 0);
    }

    function test_priceHelpers_smoke() public pure {
        // Hit the remaining “price helpers” that are otherwise only exercised in specific price-oracle style paths.
        IGyroECLPPool.EclpParams memory p;
        p.alpha = int256(9e17);
        p.beta = int256(11e17);
        p.c = int256(1e18);
        p.s = int256(0);
        p.lambda = int256(1e18);

        // Use derived params from the file’s own math (simple, no-rotation case).
        IGyroECLPPool.DerivedEclpParams memory d;
        d.tauAlpha = GyroECLPMath.tau(p, p.alpha);
        d.tauBeta = GyroECLPMath.tau(p, p.beta);
        d.dSq = int256(1e38);
        // With s=0,c=1,lambda=1, these simplify safely.
        d.u = (d.tauBeta.x + d.tauAlpha.x) / 2;
        d.v = (d.tauBeta.y + d.tauAlpha.y) / 2;
        d.w = (d.tauBeta.y - d.tauAlpha.y) / 2;
        d.z = (d.tauBeta.x - d.tauAlpha.x) / 2;

        uint256[] memory balances = new uint256[](2);
        balances[0] = 100e18;
        balances[1] = 100e18;

        // computeOffsetFromBalances hits calculateInvariantWithError + virtualOffset{0,1} + price math.
        (int256 a, int256 b) = GyroECLPMath.computeOffsetFromBalances(balances, p, d);
        uint256 price1 = GyroECLPMath.computePrice(balances, p, a, b);
        assertGt(price1, 0);

        // clampPriceToPoolRange
        assertEq(GyroECLPMath.clampPriceToPoolRange(1, p), uint256(p.alpha));
        assertEq(GyroECLPMath.clampPriceToPoolRange(type(uint256).max, p), uint256(p.beta));

        // calcSpotPrice0in1 (requires invariant; use a small positive constant)
        uint256 price0in1 = GyroECLPMath.calcSpotPrice0in1(balances, p, d, int256(1e18));
        assertGt(price0in1, 0);
    }
}

