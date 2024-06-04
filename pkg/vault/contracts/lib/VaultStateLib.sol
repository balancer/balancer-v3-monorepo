// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { VaultState } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

library VaultStateLib {
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
