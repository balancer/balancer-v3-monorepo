// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

/**
 * @dev Calls into Vault.unlock, which then calls back into this contract, allowing us to call
 * Vault-onlyWhenUnlocked functions without going through routers.
 */
contract UnlockCallerMock {
    IVault private immutable _vault;

    constructor(IVault vault_) {
        _vault = vault_;
    }

    function unlockAndCall(bytes calldata callbackData) external returns (bytes memory) {
        return _vault.unlock(callbackData);
    }

    function cbAddLiquidity(AddLiquidityParams calldata params) external returns (bytes memory) {
        _vault.addLiquidity(params);
        return bytes("");
    }

    function cbRemoveLiquidity(RemoveLiquidityParams calldata params) external returns (bytes memory) {
        _vault.removeLiquidity(params);
        return bytes("");
    }

    function cbWrapOrUnwrap(BufferWrapOrUnwrapParams calldata params) external returns (bytes memory) {
        _vault.erc4626BufferWrapOrUnwrap(params);
        return bytes("");
    }
}
