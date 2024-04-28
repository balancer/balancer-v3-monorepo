// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IProtocolFeeCollector } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeCollector.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";
import { EnumerableSet } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

contract ProtocolFeeCollector is IProtocolFeeCollector, Authentication, ReentrancyGuardTransient {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    IVault private immutable _vault;

    EnumerableSet.AddressSet private _denylistedTokens;

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
    function isWithdrawableToken(IERC20 token) public view returns (bool) {
        return _denylistedTokens.contains(address(token)) == false;
    }

    /// @inheritdoc IProtocolFeeCollector
    function isWithdrawableTokens(IERC20[] calldata tokens) external view returns (bool) {
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (isWithdrawableToken(tokens[i]) == false) {
                return false;
            }
        }

        return true;
    }

    /// @inheritdoc IProtocolFeeCollector
    function getDenylistedToken(uint256 index) external view returns (IERC20) {
        return IERC20(_denylistedTokens.at(index));
    }

    /// @inheritdoc IProtocolFeeCollector
    function getDenylistedTokensLength() external view returns (uint256) {
        return _denylistedTokens.length();
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

            if (isWithdrawableToken(token) == false) {
                revert TokenOnDenyList(token);
            }

            uint256 amount = token.balanceOf(address(this));

            token.safeTransfer(recipient, amount);

            emit ProtocolFeeWithdrawn(token, amount, recipient);
        }
    }

    /// @inheritdoc IProtocolFeeCollector
    function denylistToken(IERC20 token) external authenticate {
        _denylistToken(token);
    }

    /// @inheritdoc IProtocolFeeCollector
    function allowlistToken(IERC20 token) external authenticate {
        _allowlistToken(token);
    }

    // Internal functions

    function _denylistToken(IERC20 token) internal {
        if (_denylistedTokens.add(address(token)) == false) {
            revert TokenOnDenyList(token);
        }

        emit TokenDenylisted(token);
    }

    function _allowlistToken(IERC20 token) internal {
        if (_denylistedTokens.remove(address(token)) == false) {
            revert TokenNotOnDenyList(token);
        }

        emit TokenAllowlisted(token);
    }

    /// @inheritdoc Authentication
    function _canPerform(bytes32 actionId, address user) internal view virtual override returns (bool) {
        return _vault.getAuthorizer().canPerform(actionId, user, address(this));
    }
}
