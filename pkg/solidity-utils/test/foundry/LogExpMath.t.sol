// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "../../contracts/math/LogExpMath.sol";
import "../../contracts/test/LogExpMathMock.sol";

contract LogExpMathTest is Test {
    uint256 internal constant EXPECTED_RELATIVE_ERROR = 1e3;
    int256 constant ONE_18 = 1e18;
    int256 constant ONE_20 = 1e20;
    uint256 constant MILD_EXPONENT_BOUND = 2 ** 254 / uint256(ONE_20);
    LogExpMathMock mock;

    function setUp() public {
        mock = new LogExpMathMock();
    }

    function testPow() external {
        assertApproxEqAbs(LogExpMath.pow(2e18, 2e18), 4e18, 100);
    }

    function testPowMatchesJSFuzzed(uint256 base, uint256 exponent) external {
        base = bound(base, 0, 10);
        exponent = bound(exponent, 0, MILD_EXPONENT_BOUND - 1);

        uint256 pow;
        try mock.pow(base, exponent) returns (uint256 ret) {
            pow = ret;
        } catch (bytes memory reason) {
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
        console.logBytes(result);
        uint256 expectedResult = abi.decode(result, (uint256)) * 1e18;

        assertApproxEqAbs(pow, expectedResult, expectedResult / EXPECTED_RELATIVE_ERROR);
    }
}
