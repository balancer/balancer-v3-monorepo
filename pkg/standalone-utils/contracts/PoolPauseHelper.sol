// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IPoolPauseHelper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IPoolPauseHelper.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { PoolHelperCommon } from "./PoolHelperCommon.sol";

contract PoolPauseHelper is IPoolPauseHelper, PoolHelperCommon {
    constructor(IVault vault, address initialOwner) PoolHelperCommon(vault, initialOwner) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /***************************************************************************
                                    Manage Pools
    ***************************************************************************/

    /// @inheritdoc IPoolPauseHelper
    function pausePools(address[] memory pools) public {
        // Retrieve the poolSetId for this sender.
        uint256 poolSetId = _getValidPoolSetId();

        uint256 length = pools.length;

        for (uint256 i = 0; i < length; i++) {
            address pool = pools[i];
            _ensurePoolInSet(poolSetId, pool);

            vault.pausePool(pool);
        }
    }
}
