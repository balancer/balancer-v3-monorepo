// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IProtocolFeeSweeper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeSweeper.sol";

import { FeeBurnerAuthentication } from "../FeeBurnerAuthentication.sol";

contract FeeBurnerAuthenticationMock is FeeBurnerAuthentication {
    constructor(
        IVault vault,
        IProtocolFeeSweeper protocolFeeSweeper
    ) FeeBurnerAuthentication(vault, protocolFeeSweeper) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function manualOnlyProtocolFeeSweeper() external onlyProtocolFeeSweeper {}

    function manualOnlyFeeRecipientOrGovernance() external onlyFeeRecipientOrGovernance {}
}
