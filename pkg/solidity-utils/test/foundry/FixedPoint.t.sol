// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { FixedPoint } from "../../contracts/math/FixedPoint.sol";

contract FixedPointTest is Test {
    function testComplement__Fuzz(uint256 x) external pure {
        uint256 complement = FixedPoint.complement(x);

        if (x < FixedPoint.ONE) {
            assertEq(complement, FixedPoint.ONE - x);
        } else {
            assertEq(complement, 0);
        }
    }

    function testComplementEquivalence__Fuzz(uint256 x) external pure {
        uint256 referenceComplement = (x < FixedPoint.ONE) ? (FixedPoint.ONE - x) : 0;
        uint256 complement = FixedPoint.complement(x);

        assertEq(complement, referenceComplement);
    }

    function testMulDown__Fuzz(uint256 a, uint256 b) external {
        unchecked {
            uint256 product = a * b;
            if (a != 0 && product / a != b) {
                vm.expectRevert(stdError.arithmeticError);
                FixedPoint.mulDown(a, b);
            } else {
                uint256 mulDown = FixedPoint.mulDown(a, b);

                assertLe(mulDown, (a * b) / FixedPoint.ONE);
                if (mulDown < type(uint256).max) {
                    assertGe(mulDown + 1, (a * b) / FixedPoint.ONE);
                }
            }
        }
    }

    function testMulUp__Fuzz(uint256 a, uint256 b) external {
        unchecked {
            uint256 product = a * b;
            if (a != 0 && product / a != b) {
                vm.expectRevert(stdError.arithmeticError);
                FixedPoint.mulUp(a, b);
            } else {
                uint256 mulUp = FixedPoint.mulUp(a, b);

                assertGe(mulUp, (a * b) / FixedPoint.ONE);
                if (mulUp > 0) {
                    assertLe(mulUp - 1, (a * b) / FixedPoint.ONE);
                }
            }
        }
    }

    function testMulUpEquivalence__Fuzz(uint256 a, uint256 b) external pure {
        unchecked {
            uint256 product = a * b;
            vm.assume(a == 0 || product / a == b);

            uint256 referenceMulUp = product == 0 ? 0 : ((product - 1) / FixedPoint.ONE) + 1;
            uint256 mulUp = FixedPoint.mulUp(a, b);

            assertEq(mulUp, referenceMulUp);
        }
    }

    function testDivDown__Fuzz(uint256 a, uint256 b) external {
        unchecked {
            if (b == 0) {
                // check for overflow: `divDown` will fail first because of the overflow, and then because of dividing by 0.
                if ((a * FixedPoint.ONE) / FixedPoint.ONE != a) {
                    vm.expectRevert(stdError.arithmeticError);
                } else {
                    vm.expectRevert(stdError.divisionError);
                }
                FixedPoint.divDown(a, b);
            } else if (a != 0 && (a * FixedPoint.ONE) / FixedPoint.ONE != a) {
                vm.expectRevert(stdError.arithmeticError);
                FixedPoint.divDown(a, b);
            } else {
                uint256 divDown = FixedPoint.divDown(a, b);

                assertLe(divDown, (a * FixedPoint.ONE) / b);
                if (divDown < type(uint256).max) {
                    assertGe(divDown + 1, (a * FixedPoint.ONE) / b);
                }
            }
        }
    }

    function testDivDownEquivalence__Fuzz(uint256 a, uint256 b) external pure {
        unchecked {
            vm.assume(b > 0);
            vm.assume(a == 0 || (a * FixedPoint.ONE) / FixedPoint.ONE == a);

            uint256 referenceDivDown = a == 0 ? 0 : (a * FixedPoint.ONE) / b;
            uint256 divDown = FixedPoint.divDown(a, b);

            assertEq(divDown, referenceDivDown);
        }
    }

    function testDivUp__Fuzz(uint256 a, uint256 b) external {
        unchecked {
            if (b == 0) {
                // This check is required because Yul's `div` doesn't revert on b==0
                vm.expectRevert(FixedPoint.ZeroDivision.selector);
                FixedPoint.divUp(a, b);
            } else if (a != 0 && (a * FixedPoint.ONE) / FixedPoint.ONE != a) {
                vm.expectRevert(stdError.arithmeticError);
                FixedPoint.divUp(a, b);
            } else {
                uint256 divUp = FixedPoint.divUp(a, b);

                assertGe(divUp, (a * FixedPoint.ONE) / b);
                if (divUp > 0) {
                    assertLe(divUp - 1, (a * FixedPoint.ONE) / b);
                }
            }
        }
    }

    function testDivUpEquivalence__Fuzz(uint256 a, uint256 b) external pure {
        unchecked {
            vm.assume(b > 0);
            vm.assume(a == 0 || (a * FixedPoint.ONE) / FixedPoint.ONE == a);

            uint256 referenceDivUp = a == 0 ? 0 : (a * FixedPoint.ONE - 1) / b + 1;
            uint256 divUp = FixedPoint.divUp(a, b);

            assertEq(divUp, referenceDivUp);
        }
    }
}
