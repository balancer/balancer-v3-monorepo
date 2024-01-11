// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "../VaultExtension.sol";

contract VaultExtensionMock is VaultExtension {
    function mockExtensionHash(bytes calldata input) external payable returns (bytes32) {
        return keccak256(input);
    }
}
