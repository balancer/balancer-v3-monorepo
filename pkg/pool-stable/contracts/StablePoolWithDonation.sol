// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { PoolDonation } from "@balancer-labs/v3-pool-utils/contracts/PoolDonation.sol";

import { StablePool } from "./StablePool.sol";

/// @notice Standard Stable Pool with a donation mechanism.
contract StablePoolWithDonation is StablePool, PoolDonation {
    constructor(StablePool.NewPoolParams memory params, IVault vault) StablePool(params, vault) {
        // solhint-disable-previous-line no-empty-blocks
    }
}
