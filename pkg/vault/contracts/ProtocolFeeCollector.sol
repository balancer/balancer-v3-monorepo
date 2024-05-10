// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IProtocolFeeCollector } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeCollector.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

contract ProtocolFeeCollector is IProtocolFeeCollector, Authentication, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    IVault private immutable _vault;

    constructor(IVault vault_) Authentication(bytes32(uint256(uint160(address(vault_))))) {
        _vault = vault_;
    }

    /// @inheritdoc IProtocolFeeCollector
    function vault() external view returns (IVault) {
        return _vault;
    }

    /// @inheritdoc IProtocolFeeCollector
    function getAuthorizer() external view returns (IAuthorizer) {
        return _vault.getAuthorizer();
    }

    /// @inheritdoc IProtocolFeeCollector
    function getCollectedFeeAmounts(IERC20[] memory tokens) external view returns (uint256[] memory feeAmounts) {
        feeAmounts = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; ++i) {
            feeAmounts[i] = tokens[i].balanceOf(address(this));
        }
    }

    /// @inheritdoc IProtocolFeeCollector
    function withdrawCollectedFees(IERC20[] calldata tokens, address recipient) external authenticate {
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];

            uint256 amount = token.balanceOf(address(this));
            token.safeTransfer(recipient, amount);

            emit ProtocolFeeWithdrawn(token, amount, recipient);
        }
    }

    /// @inheritdoc Authentication
    function _canPerform(bytes32 actionId, address user) internal view virtual override returns (bool) {
        return _vault.getAuthorizer().canPerform(actionId, user, address(this));
    }
}
