// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IPoolPauseHelper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IPoolPauseHelper.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { PoolHelperCommon } from "./PoolHelperCommon.sol";

contract PoolPauseHelper is IPoolPauseHelper, PoolHelperCommon {
    constructor(IVault vault) PoolHelperCommon(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /***************************************************************************
                                    Manage Pools
    ***************************************************************************/

    /// @inheritdoc IPoolPauseHelper
    function pausePools(address[] memory pools) public authenticate {
        uint256 length = pools.length;
        for (uint256 i = 0; i < length; i++) {
            address pool = pools[i];
            _ensurePoolAdded(pool);

            getVault().pausePool(pool);
        }
    }
}
