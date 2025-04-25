// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IProtocolFeeHelper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeHelper.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { PoolHelperCommon } from "./PoolHelperCommon.sol";

contract ProtocolFeeHelper is IProtocolFeeHelper, PoolHelperCommon {
    using EnumerableSet for EnumerableSet.AddressSet;

    modifier withKnownPool(address pool) {
        _ensurePoolAdded(pool);
        _;
    }

    constructor(IVault vault) PoolHelperCommon(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /***************************************************************************
                                    Manage Pools
    ***************************************************************************/

    /// @inheritdoc IProtocolFeeHelper
    function setProtocolSwapFeePercentage(
        address pool,
        uint256 newProtocolSwapFeePercentage
    ) external withKnownPool(pool) authenticate {
        _getProtocolFeeController().setProtocolSwapFeePercentage(pool, newProtocolSwapFeePercentage);
    }

    /// @inheritdoc IProtocolFeeHelper
    function setProtocolYieldFeePercentage(
        address pool,
        uint256 newProtocolYieldFeePercentage
    ) external withKnownPool(pool) authenticate {
        _getProtocolFeeController().setProtocolYieldFeePercentage(pool, newProtocolYieldFeePercentage);
    }

    /***************************************************************************
                                Internal functions                                
    ***************************************************************************/

    // The protocol fee controller is upgradeable in the Vault, so we must fetch it every time.
    function _getProtocolFeeController() internal view returns (IProtocolFeeController) {
        return getVault().getProtocolFeeController();
    }
}
