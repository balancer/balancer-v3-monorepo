// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { PoolDonation } from "@balancer-labs/v3-pool-utils/contracts/PoolDonation.sol";

import { WeightedPool } from "./WeightedPool.sol";

contract WeightedPoolWithDonation is WeightedPool, PoolDonation {
    constructor(WeightedPool.NewPoolParams memory params, IVault vault) WeightedPool(params, vault) {
        // solhint-disable-previous-line no-empty-blocks
    }
}
