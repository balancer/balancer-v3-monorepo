// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IPoolSwapFeeHelper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IPoolSwapFeeHelper.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { PoolHelperCommon } from "./PoolHelperCommon.sol";

contract PoolSwapFeeHelper is IPoolSwapFeeHelper, PoolHelperCommon {
    constructor(IVault vault) PoolHelperCommon(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /***************************************************************************
                                    Manage Pools
    ***************************************************************************/

    /// @inheritdoc IPoolSwapFeeHelper
    function setStaticSwapFeePercentage(address pool, uint256 swapFeePercentage) public authenticate {
        _ensurePoolAdded(pool);

        getVault().setStaticSwapFeePercentage(pool, swapFeePercentage);
    }

    /***************************************************************************
                                Internal functions                                
    ***************************************************************************/

    /// @inheritdoc PoolHelperCommon
    function _validatePool(address pool) internal view override {
        // Pools cannot have a swap fee manager.
        if (getVault().getPoolRoleAccounts(pool).swapFeeManager != address(0)) {
            revert PoolHasSwapManager(pool);
        }
    }
}
