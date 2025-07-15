// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

contract SimpleEIP7702Contract {
    struct Call {
        bytes data;
        address to;
        uint256 value;
    }

    function execute(Call[] memory calls) external payable returns (bytes[] memory results) {
        results = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            Call memory call = calls[i];
            (bool success, bytes memory result) = call.to.call{ value: call.value }(call.data);
            require(success == true);
            results[i] = result;
        }
    }

    receive() external payable {}
}
