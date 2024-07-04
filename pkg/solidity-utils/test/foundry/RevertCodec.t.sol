// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { RevertCodec } from "../../contracts/helpers/RevertCodec.sol";

contract RevertCodecTest is Test {
    error TestCustomError(uint256 code);

    function testCatchEncodedResultNoSelector() public {
        vm.expectRevert(RevertCodec.ErrorSelectorNotFound.selector);
        RevertCodec.catchEncodedResult("");
    }

    function testCatchEncodedResultCustomError() public {
        vm.expectRevert(abi.encodeWithSelector(TestCustomError.selector, uint256(123)));
        RevertCodec.catchEncodedResult(bytes(abi.encodeWithSelector(TestCustomError.selector, uint256(123))));
    }

    function testCatchEncodedResultOk() public pure {
        bytes memory encodedError = abi.encodeWithSelector(RevertCodec.Result.selector, abi.encode(uint256(987), true));
        bytes memory result = RevertCodec.catchEncodedResult(encodedError);
        (uint256 decodedResultInt, bool decodedResultBool) = abi.decode(result, (uint256, bool));

        assertEq(decodedResultInt, uint256(987), "Wrong decoded result (int)");
        assertEq(decodedResultBool, true, "Wrong decoded result (bool)");
    }

    function testParseSelectorNoData() public {
        vm.expectRevert(RevertCodec.ErrorSelectorNotFound.selector);
        RevertCodec.parseSelector("");
    }

    function testParseSelector() public pure {
        bytes4 selector = RevertCodec.parseSelector(abi.encodePacked(hex"112233445566778899aabbccddeeff"));
        assertEq(selector, bytes4(0x11223344), "Incorrect selector");
    }
}
