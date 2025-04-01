// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    IWrappedBalancerPoolTokenFactory
} from "@balancer-labs/v3-interfaces/contracts/vault/IWrappedBalancerPoolTokenFactory.sol";
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

import { WrappedBalancerPoolToken } from "./WrappedBalancerPoolToken.sol";

/// @notice Factory contract for creating wrapped Balancer pool tokens
contract WrappedBalancerPoolTokenFactory is IWrappedBalancerPoolTokenFactory, SingletonAuthentication {
    bool private _isDisabled;
    mapping(address => address) internal _wrappedTokens;

    constructor(IVault vault) SingletonAuthentication(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    modifier notDisabled() {
        if (_isDisabled) {
            revert FactoryPaused();
        }
        _;
    }

    /// @inheritdoc IWrappedBalancerPoolTokenFactory
    function createWrappedToken(address balancerPoolToken) external notDisabled authenticate returns (address) {
        address wrappedToken = _wrappedTokens[balancerPoolToken];
        if (wrappedToken != address(0)) {
            revert WrappedBPTAlreadyExists(wrappedToken);
        }

        if (getVault().isPoolInitialized(address(balancerPoolToken)) == false) {
            revert BalancerPoolTokenNotInitialized();
        }

        string memory name = string(abi.encodePacked("Wrapped ", IERC20Metadata(balancerPoolToken).name()));
        string memory symbol = string(abi.encodePacked("w", IERC20Metadata(balancerPoolToken).symbol()));
        wrappedToken = address(new WrappedBalancerPoolToken(getVault(), IERC20(balancerPoolToken), name, symbol));

        _wrappedTokens[address(balancerPoolToken)] = wrappedToken;
        emit WrappedTokenCreated(balancerPoolToken, wrappedToken);

        return address(wrappedToken);
    }

    /// @inheritdoc IWrappedBalancerPoolTokenFactory
    function getWrappedToken(address balancerPoolToken) external view returns (address) {
        return _wrappedTokens[balancerPoolToken];
    }

    /// @inheritdoc IWrappedBalancerPoolTokenFactory
    function setDisabled(bool disabled) external {
        _isDisabled = disabled;
    }

    /// @inheritdoc IWrappedBalancerPoolTokenFactory
    function isDisabled() external view returns (bool) {
        return _isDisabled;
    }
}
