// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { PoolHelperCommon } from "../PoolHelperCommon.sol";

contract PoolHelperMock is PoolHelperCommon {
    constructor(IVault vault, address initialOwner) PoolHelperCommon(vault, initialOwner) {
        // solhint-disable-previous-line no-empty-blocks
    }
}
