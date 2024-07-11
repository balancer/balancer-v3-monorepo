// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BasePoolFactory } from "../BasePoolFactory.sol";

contract BasePoolFactoryMock is BasePoolFactory {
    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        bytes memory creationCode
    ) BasePoolFactory(vault, pauseWindowDuration, creationCode) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getCreationCode() external returns (bytes memory) {
        return _creationCode;
    }

    function manualEnsureEnabled() external view {
        _ensureEnabled();
    }
}
