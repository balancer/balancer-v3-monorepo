// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "../../contracts/math/LogExpMath.sol";
import "../../contracts/test/LogExpMathMock.sol";

contract LogExpMathTest is Test {
    uint256 internal constant EXPECTED_RELATIVE_ERROR = 1e4;
    uint256 constant ONE_18 = 1e18;
    uint256 constant ONE_20 = 1e20;
    uint256 constant MILD_EXPONENT_BOUND = 2 ** 254 / uint256(ONE_20);
    uint256 constant UPPER_BASE_BOUND = 1e10 * ONE_18;
    uint256 constant LOWER_BASE_BOUND = 1e4;
    uint256 constant UPPER_EXPONENT_BOUND = 1e3 * ONE_18;
    uint256 constant LOWER_EXPONENT_BOUND = 1e6;
    LogExpMathMock mock;

    function setUp() public {
        mock = new LogExpMathMock();
    }

    function testPow() external {
        assertApproxEqAbs(LogExpMath.pow(2e18, 2e18), 4e18, 100);
    }

    function testPowMatchesJSFuzzed(uint256 base, uint256 exponent) external {
        base = bound(base, LOWER_BASE_BOUND, UPPER_BASE_BOUND);
        exponent = bound(exponent, LOWER_EXPONENT_BOUND, UPPER_EXPONENT_BOUND);

        uint256 pow;
        try mock.pow(base, exponent) returns (uint256 ret) {
            pow = ret;
        } catch (bytes memory reason) {
            // abandon the run if we get one of the expected errors
            vm.assume(
                !(LogExpMath.ProductOutOfBounds.selector == bytes4(reason) ||
                    LogExpMath.ExponentOutOfBounds.selector == bytes4(reason) ||
                    LogExpMath.BaseOutOfBounds.selector == bytes4(reason))
            );
            revert("Unhandled error occurred.");
        }

        string[] memory bashInput = new string[](4);

        // Build ffi command string
        bashInput[0] = "node";
        bashInput[1] = "./scripts/pow.js";
        bashInput[2] = Strings.toString(base);
        bashInput[3] = Strings.toString(exponent);

        // Run command and capture output
        bytes memory result = vm.ffi(bashInput);
        uint256 expectedResult = abi.decode(result, (uint256));

        assertApproxEqAbs(pow, expectedResult, expectedResult / EXPECTED_RELATIVE_ERROR);
    }
}
