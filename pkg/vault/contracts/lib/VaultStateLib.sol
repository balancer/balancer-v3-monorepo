// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

// @notice Config type to store entire configuration of the vault
type VaultStateBits is bytes32;

using VaultStateLib for VaultStateBits global;

library VaultStateLib {
    using WordCodec for bytes32;
    using SafeCast for uint256;

    // Bit offsets for pool config
    uint8 public constant QUERY_DISABLED_OFFSET = 0;
    uint8 public constant VAULT_PAUSED_OFFSET = QUERY_DISABLED_OFFSET + 1;

    uint8 public constant PROTOCOL_SWAP_FEE_OFFSET = VAULT_PAUSED_OFFSET + 1;
    uint8 public constant PROTOCOL_YIELD_FEE_OFFSET = PROTOCOL_SWAP_FEE_OFFSET + _FEE_BITLENGTH;

    // Protocol Swap and Yield Fees are a 10 bits value. We transform it by multiplying by 1e15, so
    // it can be configured from 0% to 100% fee (step 0.1%)
    uint8 private constant _FEE_BITLENGTH = 10;
    uint64 public constant FEE_SCALING_FACTOR = 1e15;

    function isQueryDisabled(VaultStateBits config) internal pure returns (bool) {
        return VaultStateBits.unwrap(config).decodeBool(QUERY_DISABLED_OFFSET);
    }

    function isVaultPaused(VaultStateBits config) internal pure returns (bool) {
        return VaultStateBits.unwrap(config).decodeBool(VAULT_PAUSED_OFFSET);
    }

    function getProtocolSwapFeePercentage(VaultStateBits config) internal pure returns (uint64) {
        return
            VaultStateBits.unwrap(config).decodeUint(PROTOCOL_SWAP_FEE_OFFSET, _FEE_BITLENGTH).toUint64() *
            FEE_SCALING_FACTOR;
    }

    function getProtocolYieldFeePercentage(VaultStateBits config) internal pure returns (uint64) {
        return
            VaultStateBits.unwrap(config).decodeUint(PROTOCOL_YIELD_FEE_OFFSET, _FEE_BITLENGTH).toUint64() *
            FEE_SCALING_FACTOR;
    }

    function fromVaultState(VaultState memory config) internal pure returns (VaultStateBits) {
        bytes32 configBits = bytes32(0);

        configBits = configBits
            .insertBool(config.isQueryDisabled, QUERY_DISABLED_OFFSET)
            .insertBool(config.isVaultPaused, VAULT_PAUSED_OFFSET)
            .insertUint(config.protocolSwapFeePercentage / FEE_SCALING_FACTOR, PROTOCOL_SWAP_FEE_OFFSET, _FEE_BITLENGTH)
            .insertUint(
                config.protocolYieldFeePercentage / FEE_SCALING_FACTOR,
                PROTOCOL_YIELD_FEE_OFFSET,
                _FEE_BITLENGTH
            );

        return VaultStateBits.wrap(configBits);
    }

    function toVaultState(VaultStateBits config) internal pure returns (VaultState memory) {
        return
            VaultState({
                isQueryDisabled: config.isQueryDisabled(),
                isVaultPaused: config.isVaultPaused(),
                protocolSwapFeePercentage: config.getProtocolSwapFeePercentage(),
                protocolYieldFeePercentage: config.getProtocolYieldFeePercentage()
            });
    }
}
