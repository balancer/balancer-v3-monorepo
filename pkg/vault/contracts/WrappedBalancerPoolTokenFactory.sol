// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    IWrappedBalancerPoolTokenFactory
} from "@balancer-labs/v3-interfaces/contracts/vault/IWrappedBalancerPoolTokenFactory.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { WrappedBalancerPoolToken } from "./WrappedBalancerPoolToken.sol";

/// @notice Factory contract for creating wrapped Balancer pool tokens.
contract WrappedBalancerPoolTokenFactory is IWrappedBalancerPoolTokenFactory {
    IVault internal immutable _vault;

    // Maintain a mapping between the raw BPT and the wrapped version.
    mapping(address poolToken => address wrappedPoolToken) internal _wrappedTokens;

    constructor(IVault vault) {
        _vault = vault;
    }

    /// @inheritdoc IWrappedBalancerPoolTokenFactory
    function getVault() external view returns (IVault) {
        return _vault;
    }

    /// @inheritdoc IWrappedBalancerPoolTokenFactory
    function createWrappedToken(address balancerPoolToken) external returns (address) {
        address wrappedToken = _wrappedTokens[balancerPoolToken];
        if (wrappedToken != address(0)) {
            revert WrappedBPTAlreadyExists(wrappedToken);
        }

        if (_vault.isPoolRegistered(address(balancerPoolToken)) == false) {
            revert BalancerPoolTokenNotRegistered();
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
