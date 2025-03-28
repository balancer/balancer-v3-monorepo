// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    IWrappedBalancerPoolTokenFactory
} from "@balancer-labs/v3-interfaces/contracts/vault/IWrappedBalancerPoolTokenFactory.sol";

import { WrappedBalancerPoolToken } from "./WrappedBalancerPoolToken.sol";

/// @notice Factory contract for creating wrapped Balancer pool tokens
contract WrappedBalancerPoolTokenFactory is IWrappedBalancerPoolTokenFactory {
    IVault internal immutable _vault;
    mapping(address => address) internal _wrappedTokens;

    constructor(IVault vault) {
        _vault = vault;
    }

    /// @inheritdoc IWrappedBalancerPoolTokenFactory
    function createWrappedToken(address balancerPoolToken) external returns (address) {
        address wrappedToken = _wrappedTokens[balancerPoolToken];
        if (wrappedToken != address(0)) {
            revert WrappedBPTAlreadyExists(wrappedToken);
        }

        if (_vault.isPoolInitialized(address(balancerPoolToken)) == false) {
            revert BalancerPoolTokenNotInitialized();
        }

        string memory name = string(abi.encodePacked("Wrapped ", IERC20Metadata(balancerPoolToken).name()));
        string memory symbol = string(abi.encodePacked("w", IERC20Metadata(balancerPoolToken).symbol()));
        wrappedToken = address(new WrappedBalancerPoolToken(_vault, IERC20(balancerPoolToken), name, symbol));

        _wrappedTokens[address(balancerPoolToken)] = wrappedToken;
        emit WrappedTokenCreated(balancerPoolToken, wrappedToken);

        return address(wrappedToken);
    }

    /// @inheritdoc IWrappedBalancerPoolTokenFactory
    function getWrappedToken(address balancerPoolToken) external view returns (address) {
        return _wrappedTokens[balancerPoolToken];
    }
}
