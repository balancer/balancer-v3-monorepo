// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { PoolDonation } from "@balancer-labs/v3-pool-utils/contracts/PoolDonation.sol";

import { PoolMockCommon } from "./PoolMockCommon.sol";

contract PoolMockWithDonation is PoolMockCommon, PoolDonation {
    constructor(IVault vault, string memory name, string memory symbol) PoolMockCommon(vault, name, symbol) {
        // solhint-previous-line no-empty-blocks
    }
}
