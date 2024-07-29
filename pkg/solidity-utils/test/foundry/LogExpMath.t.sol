// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

import { LogExpMath } from "../../contracts/math/LogExpMath.sol";
import { LogExpMathMock } from "../../contracts/test/LogExpMathMock.sol";

contract LogExpMathTest is Test {
    uint256 internal constant EXPECTED_RELATIVE_ERROR = 1e4;
    uint256 constant ONE_18 = 1e18;
    uint256 constant ONE_20 = 1e20;
    uint256 constant MILD_EXPONENT_BOUND = 2 ** 254 / uint256(ONE_20);
    uint256 constant UPPER_BASE_BOUND = 1e7 * ONE_18;
    uint256 constant LOWER_BASE_BOUND = 1e15;
    uint256 constant UPPER_EXPONENT_BOUND = 5 * ONE_18;
    uint256 constant LOWER_EXPONENT_BOUND = 1e14;
    LogExpMathMock mock;

    function setUp() public {
        mock = new LogExpMathMock();
    }

    function testPow() external pure {
        assertApproxEqAbs(LogExpMath.pow(2e18, 2e18), 4e18, 100);
    }

    /**
     * forge-config: default.fuzz.runs = 256
     * forge-config: intense.fuzz.runs = 10000
     */
    function testPowMatchesJS__FuzzFFI(uint256 base, uint256 exponent) external {
        base = bound(base, LOWER_BASE_BOUND, UPPER_BASE_BOUND);
        exponent = bound(exponent, LOWER_EXPONENT_BOUND, UPPER_EXPONENT_BOUND);

        uint256 pow = mock.pow(base, exponent);

        string[] memory bashInput = new string[](4);

        // Build ffi command string
        bashInput[0] = "node";
        bashInput[1] = "./scripts/pow.mjs";
        bashInput[2] = Strings.toString(base);
        bashInput[3] = Strings.toString(exponent);

        // Run command and capture output
        bytes memory result = vm.ffi(bashInput);
        uint256 expectedResult = abi.decode(result, (uint256));

        uint256 delta = expectedResult / EXPECTED_RELATIVE_ERROR;
        // for delta of 0 allow precision loss of 1
        assertApproxEqAbs(pow, expectedResult, delta == 0 ? 1 : delta);
    }
}
