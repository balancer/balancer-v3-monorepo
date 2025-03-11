// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { AclAmmMath } from "../../contracts/lib/AclAmmMath.sol";

contract AclAmmMathTest is Test {
    using FixedPoint for uint256;

    uint256 private constant _MAX_BALANCE = 1e6 * 1e18;
    uint256 private constant _MIN_VIRTUAL_BALANCE = 1e18;

    function testIsPoolInRange__Fuzz(
        uint256 balance0,
        uint256 balance1,
        uint256 virtualBalance0,
        uint256 virtualBalance1,
        uint256 centerednessMargin
    ) public pure {
        balance0 = bound(balance0, 0, _MAX_BALANCE);
        balance1 = bound(balance1, 0, _MAX_BALANCE);
        virtualBalance0 = bound(virtualBalance0, _MIN_VIRTUAL_BALANCE, _MAX_BALANCE);
        virtualBalance1 = bound(virtualBalance1, _MIN_VIRTUAL_BALANCE, _MAX_BALANCE);
        centerednessMargin = bound(centerednessMargin, 0, 50e16);

        uint256[] memory balancesScaled18 = new uint256[](2);
        balancesScaled18[0] = balance0;
        balancesScaled18[1] = balance1;

        uint256[] memory virtualBalances = new uint256[](2);
        virtualBalances[0] = virtualBalance0;
        virtualBalances[1] = virtualBalance1;

        bool isInRange = AclAmmMath.isPoolInRange(balancesScaled18, virtualBalances, centerednessMargin);

        if (balance0 == 0 || balance1 == 0) {
            assertEq(isInRange, false);
        } else {
            assertEq(
                isInRange,
                AclAmmMath.calculateCenteredness(balancesScaled18, virtualBalances) >= centerednessMargin
            );
        }
    }

    function testCalculateCenteredness__Fuzz(
        uint256 balance0,
        uint256 balance1,
        uint256 virtualBalance0,
        uint256 virtualBalance1
    ) public pure {
        balance0 = bound(balance0, 0, _MAX_BALANCE);
        balance1 = bound(balance1, 0, _MAX_BALANCE);
        virtualBalance0 = bound(virtualBalance0, _MIN_VIRTUAL_BALANCE, _MAX_BALANCE);
        virtualBalance1 = bound(virtualBalance1, _MIN_VIRTUAL_BALANCE, _MAX_BALANCE);

        uint256[] memory balancesScaled18 = new uint256[](2);
        balancesScaled18[0] = balance0;
        balancesScaled18[1] = balance1;

        uint256[] memory virtualBalances = new uint256[](2);
        virtualBalances[0] = virtualBalance0;
        virtualBalances[1] = virtualBalance1;

        uint256 centeredness = AclAmmMath.calculateCenteredness(balancesScaled18, virtualBalances);

        if (balance0 == 0 || balance1 == 0) {
            assertEq(centeredness, 0);
        } else if (AclAmmMath.isAboveCenter(balancesScaled18, virtualBalances)) {
            assertEq(centeredness, balance1.mulDown(virtualBalance0).divDown(balance0.mulDown(virtualBalance1)));
        } else {
            assertEq(centeredness, balance0.mulDown(virtualBalance1).divDown(balance1.mulDown(virtualBalance0)));
        }
    }

    function testIsAboveCenter__Fuzz(
        uint256 balance0,
        uint256 balance1,
        uint256 virtualBalance0,
        uint256 virtualBalance1
    ) public pure {
        balance0 = bound(balance0, 0, _MAX_BALANCE);
        balance1 = bound(balance1, 0, _MAX_BALANCE);
        virtualBalance0 = bound(virtualBalance0, _MIN_VIRTUAL_BALANCE, _MAX_BALANCE);
        virtualBalance1 = bound(virtualBalance1, _MIN_VIRTUAL_BALANCE, _MAX_BALANCE);

        uint256[] memory balancesScaled18 = new uint256[](2);
        balancesScaled18[0] = balance0;
        balancesScaled18[1] = balance1;

        uint256[] memory virtualBalances = new uint256[](2);
        virtualBalances[0] = virtualBalance0;
        virtualBalances[1] = virtualBalance1;

        bool isAboveCenter = AclAmmMath.isAboveCenter(balancesScaled18, virtualBalances);

        if (balance0 == 0) {
            assertEq(isAboveCenter, false);
        } else if (balance1 == 0) {
            assertEq(isAboveCenter, true);
        } else {
            assertEq(isAboveCenter, balance0.divDown(balance1) > virtualBalance0.divDown(virtualBalance1));
        }
    }

    function testCalculateSqrtQ0__Fuzz(
        uint256 currentTime,
        uint256 startSqrtQ0,
        uint256 endSqrtQ0,
        uint256 startTime,
        uint256 endTime
    ) public pure {
        endTime = bound(endTime, 2, type(uint64).max);
        startTime = bound(startTime, 1, endTime - 1);
        currentTime = bound(currentTime, startTime, endTime);

        endSqrtQ0 = bound(endSqrtQ0, 1, type(uint128).max);
        startSqrtQ0 = bound(endSqrtQ0, 1, type(uint128).max);

        uint256 sqrtQ0 = AclAmmMath.calculateSqrtQ0(currentTime, startSqrtQ0, endSqrtQ0, startTime, endTime);

        currentTime++;
        uint256 nextSqrtQ0 = AclAmmMath.calculateSqrtQ0(currentTime, startSqrtQ0, endSqrtQ0, startTime, endTime);

        if (startSqrtQ0 >= endSqrtQ0) {
            assertLe(nextSqrtQ0, sqrtQ0, "Next sqrtQ0 should be less than current sqrtQ0");
        } else {
            assertGe(nextSqrtQ0, sqrtQ0, "Next sqrtQ0 should be greater than current sqrtQ0");
        }
    }

    function testCalculateSqrtQ0WhenCurrentTimeIsAfterEndTime() public pure {
        uint256 startSqrtQ0 = 100;
        uint256 endSqrtQ0 = 200;
        uint256 startTime = 0;
        uint256 endTime = 50;
        uint256 currentTime = 100;

        uint256 sqrtQ0 = AclAmmMath.calculateSqrtQ0(currentTime, startSqrtQ0, endSqrtQ0, startTime, endTime);

        assertEq(sqrtQ0, endSqrtQ0, "SqrtQ0 should be equal to endSqrtQ0");
    }

    function testCalculateSqrtQ0WhenCurrentTimeIsBeforeStartTime() public pure {
        uint256 startSqrtQ0 = 100;
        uint256 endSqrtQ0 = 200;
        uint256 startTime = 50;
        uint256 endTime = 100;
        uint256 currentTime = 0;

        uint256 sqrtQ0 = AclAmmMath.calculateSqrtQ0(currentTime, startSqrtQ0, endSqrtQ0, startTime, endTime);

        assertEq(sqrtQ0, startSqrtQ0, "SqrtQ0 should be equal to startSqrtQ0");
    }
}
