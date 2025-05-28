// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IProtocolFeeSweeper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeSweeper.sol";
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

contract FeeBurnerAuthentication is SingletonAuthentication {
    IProtocolFeeSweeper public immutable protocolFeeSweeper;

    /// @notice The fee protocol is invalid.
    error InvalidProtocolFeeSweeper();

    modifier onlyFeeRecipientOrGovernance() {
        address roleAddress = protocolFeeSweeper.getFeeRecipient();

        _ensureAuthenticatedByRole(address(this), roleAddress);
        _;
    }

    modifier onlyProtocolFeeSweeper() {
        if (msg.sender != address(protocolFeeSweeper)) {
            revert SenderNotAllowed();
        }
        _;
    }

    constructor(IVault vault, IProtocolFeeSweeper _protocolFeeSweeper) SingletonAuthentication(vault) {
        if (address(_protocolFeeSweeper) == address(0)) {
            revert InvalidProtocolFeeSweeper();
        }

        protocolFeeSweeper = _protocolFeeSweeper;
    }
}
