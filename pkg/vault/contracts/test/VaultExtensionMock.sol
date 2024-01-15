// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import "../VaultExtension.sol";

contract VaultExtensionMock is VaultExtension {
    constructor(IVault vault) VaultExtension(vault) {}

    function mockExtensionHash(bytes calldata input) external payable returns (bytes32) {
        return keccak256(input);
    }
}
