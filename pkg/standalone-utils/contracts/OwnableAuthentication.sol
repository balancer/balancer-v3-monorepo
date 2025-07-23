// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";

/**
 * @notice OwnableAuthentication is a contract that combines ownership management with authentication.
 * @dev Use it to pre-wire admin multisigs upon deployment to a contract that requires permissioned functions to work,
 * where the impact of the owner going rogue is minimal. Contract registries, fee burners, and other utility contracts
 * are good examples.
 * In turn, the pre-configured owner can speed up operations as it can perform any action right after deployment without
 * waiting for governance to set up the authorizer, which can take whole weeks.
 * On the other hand, governance can always revoke or change the owner at any given time, keeping superior powers
 * above the owner.
 */
contract OwnableAuthentication is Ownable2Step, Authentication {
    /// @notice The vault has not been set.
    error VaultNotSet();

    IVault public immutable vault;

    constructor(
        IVault vault_,
        address initialOwner
    ) Ownable(initialOwner) Authentication(bytes32(uint256(uint160(address(this))))) {
        if (address(vault_) == address(0)) {
            revert VaultNotSet();
        }

        vault = vault_;
    }

    /// @notice Returns the authorizer address according to the Vault.
    function getAuthorizer() external view returns (IAuthorizer) {
        return vault.getAuthorizer();
    }

    /**
     * @notice Transfer ownership without the 2-step process. It cannot be called by the current owner; governance only.
     * @dev This allows governance to revoke the owner at any time, preserving control above the owner at all times.
     * address(0) is also a valid owner, as governance can simply choose to revoke ownership.
     * Ownership can always be forced back to any address later on.
     */
    function forceTransferOwnership(address newOwner) external authenticate {
        // `authenticate` let's the owner through, so we filter it out here.
        if (msg.sender == owner()) {
            revert SenderNotAllowed();
        }
        _transferOwnership(newOwner);
    }

    function _canPerform(bytes32 actionId, address user) internal view virtual override returns (bool) {
        // The owner is always allowed to perform any action.
        if (user == owner()) {
            return true;
        }

        // Otherwise, check the vault's authorizer for permission.
        return vault.getAuthorizer().canPerform(actionId, user, address(this));
    }
}
