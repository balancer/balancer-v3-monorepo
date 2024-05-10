// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import {
    FEE_BITLENGTH,
    FEE_SCALING_FACTOR,
    VaultState
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

// @notice Config type to store entire configuration of the vault
type VaultStateBits is bytes32;

using VaultStateLib for VaultStateBits global;

library VaultStateLib {
    using WordCodec for bytes32;

    // Bit offsets for pool config
    uint256 public constant QUERY_DISABLED_OFFSET = 0;
    uint256 public constant VAULT_PAUSED_OFFSET = QUERY_DISABLED_OFFSET + 1;
    uint256 public constant BUFFER_PAUSED_OFFSET = VAULT_PAUSED_OFFSET + 1;

    uint256 public constant PROTOCOL_SWAP_FEE_OFFSET = BUFFER_PAUSED_OFFSET + 1;
    uint256 public constant PROTOCOL_YIELD_FEE_OFFSET = PROTOCOL_SWAP_FEE_OFFSET + FEE_BITLENGTH;

    function isQueryDisabled(VaultStateBits config) internal pure returns (bool) {
        return VaultStateBits.unwrap(config).decodeBool(QUERY_DISABLED_OFFSET);
    }

    function isVaultPaused(VaultStateBits config) internal pure returns (bool) {
        return VaultStateBits.unwrap(config).decodeBool(VAULT_PAUSED_OFFSET);
    }

    function areBuffersPaused(VaultStateBits config) internal pure returns (bool) {
        return VaultStateBits.unwrap(config).decodeBool(BUFFER_PAUSED_OFFSET);
    }

    function getProtocolSwapFeePercentage(VaultStateBits config) internal pure returns (uint256) {
        return VaultStateBits.unwrap(config).decodeUint(PROTOCOL_SWAP_FEE_OFFSET, FEE_BITLENGTH) * FEE_SCALING_FACTOR;
    }

    function getProtocolYieldFeePercentage(VaultStateBits config) internal pure returns (uint256) {
        return VaultStateBits.unwrap(config).decodeUint(PROTOCOL_YIELD_FEE_OFFSET, FEE_BITLENGTH) * FEE_SCALING_FACTOR;
    }

    function fromVaultState(VaultState memory config) internal pure returns (VaultStateBits) {
        bytes32 configBits = bytes32(0);

        {
            configBits = configBits
                .insertBool(config.isQueryDisabled, QUERY_DISABLED_OFFSET)
                .insertBool(config.isVaultPaused, VAULT_PAUSED_OFFSET)
                .insertBool(config.areBuffersPaused, BUFFER_PAUSED_OFFSET);
        }
        {
            configBits = configBits
                .insertUint(
                    config.protocolSwapFeePercentage / FEE_SCALING_FACTOR,
                    PROTOCOL_SWAP_FEE_OFFSET,
                    FEE_BITLENGTH
                )
                .insertUint(
                    config.protocolYieldFeePercentage / FEE_SCALING_FACTOR,
                    PROTOCOL_YIELD_FEE_OFFSET,
                    FEE_BITLENGTH
                );
        }

        return VaultStateBits.wrap(configBits);
    }

    function toVaultState(VaultStateBits config) internal pure returns (VaultState memory) {
        return
            VaultState({
                isQueryDisabled: config.isQueryDisabled(),
                isVaultPaused: config.isVaultPaused(),
                areBuffersPaused: config.areBuffersPaused(),
                protocolSwapFeePercentage: config.getProtocolSwapFeePercentage(),
                protocolYieldFeePercentage: config.getProtocolYieldFeePercentage()
            });
    }
}
