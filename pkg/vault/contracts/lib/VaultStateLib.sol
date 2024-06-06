// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { VaultState } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

// @notice Config type to store entire configuration of the vault
type VaultStateBits is bytes32;

using VaultStateLib for VaultStateBits global;

library VaultStateLib {
    using WordCodec for bytes32;

    // Bit offsets for pool config
    uint256 public constant QUERY_DISABLED_OFFSET = 0;
    uint256 public constant VAULT_PAUSED_OFFSET = QUERY_DISABLED_OFFSET + 1;
    uint256 public constant BUFFER_PAUSED_OFFSET = VAULT_PAUSED_OFFSET + 1;

    function isQueryDisabled(VaultStateBits config) internal pure returns (bool) {
        return VaultStateBits.unwrap(config).decodeBool(QUERY_DISABLED_OFFSET);
    }

    function isVaultPaused(VaultStateBits config) internal pure returns (bool) {
        return VaultStateBits.unwrap(config).decodeBool(VAULT_PAUSED_OFFSET);
    }

    function areBuffersPaused(VaultStateBits config) internal pure returns (bool) {
        return VaultStateBits.unwrap(config).decodeBool(BUFFER_PAUSED_OFFSET);
    }

    function fromVaultState(VaultState memory config) internal pure returns (VaultStateBits) {
        return
            VaultStateBits.wrap(
                bytes32(0)
                    .insertBool(config.isQueryDisabled, QUERY_DISABLED_OFFSET)
                    .insertBool(config.isVaultPaused, VAULT_PAUSED_OFFSET)
                    .insertBool(config.areBuffersPaused, BUFFER_PAUSED_OFFSET)
            );
    }

    function toVaultState(VaultStateBits config) internal pure returns (VaultState memory) {
        return
            VaultState({
                isQueryDisabled: config.isQueryDisabled(),
                isVaultPaused: config.isVaultPaused(),
                areBuffersPaused: config.areBuffersPaused()
            });
    }
}
