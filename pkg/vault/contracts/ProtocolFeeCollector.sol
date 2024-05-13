// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IProtocolFeeCollector } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeCollector.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import {
    SingletonAuthentication
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/SingletonAuthentication.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

contract ProtocolFeeCollector is IProtocolFeeCollector, SingletonAuthentication, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    // Maximum protocol swap fee percentage. 1e18 corresponds to a 100% fee.
    uint256 internal constant _MAX_PROTOCOL_SWAP_FEE_PERCENTAGE = 50e16; // 50%

    // Maximum protocol yield fee percentage.
    uint256 internal constant _MAX_PROTOCOL_YIELD_FEE_PERCENTAGE = 20e16; // 20%

    IVault private immutable _vault;

    uint256 private _protocolSwapFeePercentage;

    uint256 private _protocolYieldFeePercentage;

    constructor(IVault vault_) SingletonAuthentication(vault_) {
        _vault = vault_;
    }

    /// @inheritdoc IProtocolFeeCollector
    function getMaxProtocolSwapFeePercentage() external pure returns (uint256) {
        return _MAX_PROTOCOL_SWAP_FEE_PERCENTAGE;
    }

    /// @inheritdoc IProtocolFeeCollector
    function getMaxProtocolYieldFeePercentage() external pure returns (uint256) {
        return _MAX_PROTOCOL_YIELD_FEE_PERCENTAGE;
    }

    /// @inheritdoc IProtocolFeeCollector
    function getProtocolSwapFeePercentage() external view returns (uint256) {
        return _protocolSwapFeePercentage;
    }

    /// @inheritdoc IProtocolFeeCollector
    function getProtocolYieldFeePercentage() external view returns (uint256) {
        return _protocolYieldFeePercentage;
    }

    /// @inheritdoc IProtocolFeeCollector
    function setProtocolSwapFeePercentage(uint256 newProtocolSwapFeePercentage) external authenticate {
        if (newProtocolSwapFeePercentage > _MAX_PROTOCOL_SWAP_FEE_PERCENTAGE) {
            revert ProtocolSwapFeePercentageTooHigh();
        }

        _protocolSwapFeePercentage = newProtocolSwapFeePercentage;
        emit ProtocolSwapFeePercentageChanged(newProtocolSwapFeePercentage);
    }

    /// @inheritdoc IProtocolFeeCollector
    function setProtocolYieldFeePercentage(uint256 newProtocolYieldFeePercentage) external authenticate {
        if (newProtocolYieldFeePercentage > _MAX_PROTOCOL_YIELD_FEE_PERCENTAGE) {
            revert ProtocolYieldFeePercentageTooHigh();
        }

        _protocolYieldFeePercentage = newProtocolYieldFeePercentage;
        emit ProtocolYieldFeePercentageChanged(newProtocolYieldFeePercentage);
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
}
