// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { PoolMockCommon } from "@balancer-labs/v3-vault/contracts/test/PoolMockCommon.sol";

import { PoolDonation } from "../PoolDonation.sol";

contract PoolMockWithDonation is PoolMockCommon, PoolDonation {
    constructor(IVault vault, string memory name, string memory symbol) PoolMockCommon(vault, name, symbol) {
        // solhint-previous-line no-empty-blocks
    }
}
