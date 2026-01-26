// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { Gyro2CLPMath } from "../../contracts/lib/Gyro2CLPMath.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

contract Gyro2CLPMathCoverageTest is Test {
    function test_calculateInvariant_and_virtualParams_smoke() public pure {
        uint256[] memory balances = new uint256[](2);
        balances[0] = 100e18;
        balances[1] = 100e18;

        // alpha=0.995, beta=1.005 (same params as most gyro test fixtures)
        uint256 sqrtAlpha = 997496867163000167;
        uint256 sqrtBeta = 1002496882788171068;

        uint256 inv = Gyro2CLPMath.calculateInvariant(balances, sqrtAlpha, sqrtBeta, Rounding.ROUND_DOWN);
        assertGt(inv, 0);

        // Hit the virtual param helpers too.
        assertGt(Gyro2CLPMath.calculateVirtualParameter0(inv, sqrtBeta, Rounding.ROUND_UP), 0);
        assertGt(Gyro2CLPMath.calculateVirtualParameter1(inv, sqrtAlpha, Rounding.ROUND_DOWN), 0);

        // Hit calcInGivenOut as well (calcOutGivenIn is hit by swaps + the revert test below).
        uint256 inAmt = Gyro2CLPMath.calcInGivenOut(100e18, 100e18, 1e18, 0, 0);
        assertGt(inAmt, 0);
    }

    function test_calcSpotPriceAinB_smoke() public pure {
        // Hit Gyro2CLPMath.calcSpotPriceAinB, which is not necessarily exercised by pool integration tests.
        uint256 price = Gyro2CLPMath.calcSpotPriceAinB(10e18, 3e18, 20e18, 5e18);
        assertGt(price, 0);
    }

    function test_calcOutGivenIn_assetBoundsExceeded_reverts() public {
        // Force amountOut > balanceOut by using an (intentionally invalid) large virtualOffsetOut.
        // `calcOutGivenIn` does not validate offsets; it only enforces the post-condition `amountOut <= balanceOut`.
        vm.expectRevert(Gyro2CLPMath.AssetBoundsExceeded.selector);
        Gyro2CLPMath.calcOutGivenIn(
            1e18, // balanceIn
            1e18, // balanceOut
            1e18, // amountIn
            0, // virtualOffsetIn
            2e18 // virtualOffsetOut -> makes virtOutUnder 3e18 and amountOut 1.5e18 > balanceOut
        );
    }
}
