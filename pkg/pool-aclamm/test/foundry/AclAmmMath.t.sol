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
        uint256 centernessMargin
    ) public pure {
        balance0 = bound(balance0, 0, _MAX_BALANCE);
        balance1 = bound(balance1, 0, _MAX_BALANCE);
        virtualBalance0 = bound(virtualBalance0, _MIN_VIRTUAL_BALANCE, _MAX_BALANCE);
        virtualBalance1 = bound(virtualBalance1, _MIN_VIRTUAL_BALANCE, _MAX_BALANCE);
        centernessMargin = bound(centernessMargin, 0, 50e16);

        uint256[] memory balancesScaled18 = new uint256[](2);
        balancesScaled18[0] = balance0;
        balancesScaled18[1] = balance1;

        uint256[] memory virtualBalances = new uint256[](2);
        virtualBalances[0] = virtualBalance0;
        virtualBalances[1] = virtualBalance1;

        bool isInRange = AclAmmMath.isPoolInRange(balancesScaled18, virtualBalances, centernessMargin);

        if (balance0 == 0 || balance1 == 0) {
            assertEq(isInRange, false);
        } else {
            assertEq(isInRange, AclAmmMath.calculateCenterness(balancesScaled18, virtualBalances) >= centernessMargin);
        }
    }

    function testCalculateCenterness__Fuzz(
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

        uint256 centerness = AclAmmMath.calculateCenterness(balancesScaled18, virtualBalances);

        if (balance0 == 0 || balance1 == 0) {
            assertEq(centerness, 0);
        } else if (AclAmmMath.isAboveCenter(balancesScaled18, virtualBalances)) {
            assertEq(centerness, balance1.mulDown(virtualBalance0).divDown(balance0.mulDown(virtualBalance1)));
        } else {
            assertEq(centerness, balance0.mulDown(virtualBalance1).divDown(balance1.mulDown(virtualBalance0)));
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
}
