// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IMevRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IMevRouter.sol";
import { IMevTaxCollector } from "@balancer-labs/v3-interfaces/contracts/vault/IMevTaxCollector.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { SingletonAuthentication } from "./SingletonAuthentication.sol";
import { RouterSwap } from "./RouterSwap.sol";

contract MevRouter is IMevRouter, SingletonAuthentication, RouterSwap {
    IMevTaxCollector internal mevTaxCollector;

    uint256 internal mevTaxMultiplier;
    uint256 internal priorityGasThreshold;

    bool private _isMevTaxEnabled;

    constructor(
        IVault vault,
        IWETH weth,
        IPermit2 permit2,
        string memory routerVersion,
        MevRouterParams memory params
    ) SingletonAuthentication(vault) RouterSwap(vault, weth, permit2, routerVersion) {
        mevTaxCollector = params.mevTaxCollector;
        mevTaxMultiplier = params.mevTaxMultiplier;
        priorityGasThreshold = params.priorityGasThreshold;
        _isMevTaxEnabled = true;
    }

    /// @inheritdoc IMevRouter
    function isMevTaxEnabled() external view returns (bool) {
        return _isMevTaxEnabled;
    }

    /// @inheritdoc IMevRouter
    function enableMevTax() external authenticate {
        _isMevTaxEnabled = true;
    }

    /// @inheritdoc IMevRouter
    function disableMevTax() external authenticate {
        _isMevTaxEnabled = false;
    }

    /// @inheritdoc IMevRouter
    function getMevTaxCollector() external view returns (IMevTaxCollector) {
        return mevTaxCollector;
    }

    /// @inheritdoc IMevRouter
    function setMevTaxCollector(IMevTaxCollector newMevTaxCollector) external authenticate {
        mevTaxCollector = newMevTaxCollector;
    }

    /// @inheritdoc IMevRouter
    function getMevTaxMultiplier() external view returns (uint256) {
        return mevTaxMultiplier;
    }

    /// @inheritdoc IMevRouter
    function setMevTaxMultiplier(uint256 newMevTaxMultiplier) external authenticate {
        mevTaxMultiplier = newMevTaxMultiplier;
    }

    /// @inheritdoc IMevRouter
    function getPriorityGasThreshold() external view returns (uint256) {
        return priorityGasThreshold;
    }

    /// @inheritdoc IMevRouter
    function setPriorityGasThreshold(uint256 newPriorityGasThreshold) external authenticate {
        priorityGasThreshold = newPriorityGasThreshold;
    }

    function chargeMevTax(address pool) internal {
        if (_isMevTaxEnabled == false) {
            return;
        }

        uint256 priorityGasPrice = tx.gasprice - block.basefee;

        if (priorityGasPrice < priorityGasThreshold) {
            return;
        }

        uint256 mevTax = priorityGasPrice * mevTaxMultiplier;
        mevTaxCollector.chargeMevTax{ value: mevTax }(pool);

        emit MevTaxCharged(pool, mevTax);
    }
}
