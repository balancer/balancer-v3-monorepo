// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { RawCallHelpers } from "../../contracts/helpers/RawCallHelpers.sol";

contract RawCallHelpersTest is Test {
    error TestCustomError(uint256 code);

    function testUnwrapRawCallResultSuccess() public {
        vm.expectRevert(abi.encodeWithSelector(RawCallHelpers.UnexpectedCallSuccess.selector));
        RawCallHelpers.unwrapRawCallResult(true, "");
    }

    function testUnwrapRawCallResultNoSelector() public {
        vm.expectRevert(abi.encodeWithSelector(RawCallHelpers.ErrorSelectorNotFound.selector));
        RawCallHelpers.unwrapRawCallResult(false, "");
    }

    function testUnwrapRawCallResultCustomError() public {
        vm.expectRevert(abi.encodeWithSelector(TestCustomError.selector, uint256(123)));
        RawCallHelpers.unwrapRawCallResult(
            false,
            bytes(abi.encodeWithSelector(TestCustomError.selector, uint256(123)))
        );
    }

    function testUnwrapRawCallResultOk() public {
        bytes memory encodedError = abi.encodeWithSelector(
            RawCallHelpers.Result.selector,
            abi.encode(uint256(987), true)
        );
        bytes memory result = RawCallHelpers.unwrapRawCallResult(false, encodedError);
        (uint256 decodedResultInt, bool decodedResultBool) = abi.decode(result, (uint256, bool));

        assertEq(decodedResultInt, uint256(987), "Wrong decoded result (int)");
        assertEq(decodedResultBool, true, "Wrong decoded result (bool)");
    }

    function testParseSelectorNoData() public {
        vm.expectRevert(abi.encodeWithSelector(RawCallHelpers.ErrorSelectorNotFound.selector));
        RawCallHelpers.parseSelector("");
    }

    function testParseSelector() public {
        bytes4 selector = RawCallHelpers.parseSelector(abi.encodePacked(hex"112233445566778899aabbccddeeff"));
        assertEq(selector, bytes4(0x11223344), "Incorrect selector");
    }
}
