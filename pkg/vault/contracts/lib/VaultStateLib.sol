// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { VaultState, VaultStateBits } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

library VaultStateLib {
    using WordCodec for bytes32;
    using VaultStateLib for VaultStateBits;

    // Bit offsets for pool config
    uint256 public constant QUERY_DISABLED_OFFSET = 0;
    uint256 public constant VAULT_PAUSED_OFFSET = QUERY_DISABLED_OFFSET + 1;
    uint256 public constant BUFFER_PAUSED_OFFSET = VAULT_PAUSED_OFFSET + 1;

    function isQueryDisabled(VaultStateBits memory config) internal pure returns (bool) {
        return config.bits.decodeBool(QUERY_DISABLED_OFFSET);
    }

    function setQueryDisabled(VaultStateBits memory config, bool value) internal pure {
        config.bits = config.bits.insertBool(value, QUERY_DISABLED_OFFSET);
    }

    function isVaultPaused(VaultStateBits memory config) internal pure returns (bool) {
        return config.bits.decodeBool(VAULT_PAUSED_OFFSET);
    }

    function setVaultPaused(VaultStateBits memory config, bool value) internal pure {
        config.bits = config.bits.insertBool(value, VAULT_PAUSED_OFFSET);
    }

    function areBuffersPaused(VaultStateBits memory config) internal pure returns (bool) {
        return config.bits.decodeBool(BUFFER_PAUSED_OFFSET);
    }

    function setBuffersPaused(VaultStateBits memory config, bool value) internal pure {
        config.bits = config.bits.insertBool(value, BUFFER_PAUSED_OFFSET);
    }
}
