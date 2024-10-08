// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";

contract ScalingTest is BaseTest {
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;

    function testToScaled18ApplyRateRoundDown__Fuzz(uint256 balanceRaw, uint8 decimals, uint256 rate) public pure {
        balanceRaw = bound(balanceRaw, 0, 100_000_000 * 1e18);
        decimals = uint8(bound(decimals, 0, 18));
        rate = bound(rate, 0, 100_000 * 1e18);
        uint256 decimalDiff = 18 - decimals;

        uint256 scalingFactorRaw = 10 ** decimalDiff;
        uint256 scalingFactorFp = FixedPoint.ONE * 10 ** decimalDiff;

        uint256 balanceLiveScaledWithRawScalingFactor = balanceRaw.toScaled18ApplyRateRoundDown(scalingFactorRaw, rate);
        uint256 balanceLiveScaledWithFpScalingFactor = FP_toScaled18ApplyRateRoundDown(
            balanceRaw,
            scalingFactorFp,
            rate
        );

        assertEq(
            balanceLiveScaledWithRawScalingFactor,
            balanceLiveScaledWithFpScalingFactor,
            "Scaling methods are not equivalent"
        );
    }

    function testToScaled18ApplyRateRoundUp__Fuzz(uint256 balanceRaw, uint8 decimals, uint256 rate) public pure {
        balanceRaw = bound(balanceRaw, 0, 100_000_000 * 1e18);
        decimals = uint8(bound(decimals, 0, 18));
        rate = bound(rate, 0, 100_000 * 1e18);
        uint256 decimalDiff = 18 - decimals;

        uint256 scalingFactorRaw = 10 ** decimalDiff;
        uint256 scalingFactorFp = FixedPoint.ONE * 10 ** decimalDiff;

        uint256 balanceLiveScaledWithRawScalingFactor = balanceRaw.toScaled18ApplyRateRoundUp(scalingFactorRaw, rate);
        uint256 balanceLiveScaledWithFpScalingFactor = FP_toScaled18ApplyRateRoundUp(
            balanceRaw,
            scalingFactorFp,
            rate
        );

        assertEq(
            balanceLiveScaledWithRawScalingFactor,
            balanceLiveScaledWithFpScalingFactor,
            "Scaling methods are not equivalent"
        );
    }

    function testToRawUndoRateRoundDown__Fuzz(uint256 balanceLive, uint8 decimals, uint256 rate) public pure {
        balanceLive = bound(balanceLive, 0, 100_000_000 * 1e18);
        decimals = uint8(bound(decimals, 0, 18));
        rate = bound(rate, 1, 100_000 * 1e18);
        uint256 decimalDiff = 18 - decimals;

        uint256 scalingFactorRaw = 10 ** decimalDiff;
        uint256 scalingFactorFp = FixedPoint.ONE * 10 ** decimalDiff;

        uint256 balanceRawScaledWithRawScalingFactor = balanceLive.toRawUndoRateRoundDown(scalingFactorRaw, rate);
        uint256 balanceRawScaledWithFpScalingFactor = FP_toRawUndoRateRoundDown(
            balanceLive,
            scalingFactorFp,
            rate
        );

        assertEq(
            balanceRawScaledWithRawScalingFactor,
            balanceRawScaledWithFpScalingFactor,
            "Scaling methods are not equivalent"
        );
    }

    function testToRawUndoRateRoundUp__Fuzz(uint256 balanceLive, uint8 decimals, uint256 rate) public pure {
        balanceLive = bound(balanceLive, 0, 100_000_000 * 1e18);
        decimals = uint8(bound(decimals, 0, 18));
        rate = bound(rate, 1, 100_000 * 1e18);
        uint256 decimalDiff = 18 - decimals;

        uint256 scalingFactorRaw = 10 ** decimalDiff;
        uint256 scalingFactorFp = FixedPoint.ONE * 10 ** decimalDiff;

        uint256 balanceRawScaledWithRawScalingFactor = balanceLive.toRawUndoRateRoundUp(scalingFactorRaw, rate);
        uint256 balanceRawScaledWithFpScalingFactor = FP_toRawUndoRateRoundUp(
            balanceLive,
            scalingFactorFp,
            rate
        );

        assertEq(
            balanceRawScaledWithRawScalingFactor,
            balanceRawScaledWithFpScalingFactor,
            "Scaling methods are not equivalent"
        );
    }

    /// @dev Original scaling function
    function FP_toScaled18ApplyRateRoundDown(
        uint256 amount,
        uint256 scalingFactor,
        uint256 tokenRate
    ) internal pure returns (uint256) {
        return amount.mulDown(scalingFactor).mulDown(tokenRate);
    }

    /// @dev Original scaling function
    function FP_toScaled18ApplyRateRoundUp(
        uint256 amount,
        uint256 scalingFactor,
        uint256 tokenRate
    ) internal pure returns (uint256) {
        return amount.mulUp(scalingFactor).mulUp(tokenRate);
    }

    /// @dev Original scaling function
    function FP_toRawUndoRateRoundDown(
        uint256 amount,
        uint256 scalingFactor,
        uint256 tokenRate
    ) internal pure returns (uint256) {
        // Do division last, and round scalingFactor * tokenRate up to divide by a larger number.
        return FixedPoint.divDown(amount, scalingFactor.mulUp(tokenRate));
    }

    /// @dev Original scaling function
    function FP_toRawUndoRateRoundUp(
        uint256 amount,
        uint256 scalingFactor,
        uint256 tokenRate
    ) internal pure returns (uint256) {
        // Do division last, and round scalingFactor * tokenRate down to divide by a smaller number.
        return FixedPoint.divUp(amount, scalingFactor.mulDown(tokenRate));
    }
}
