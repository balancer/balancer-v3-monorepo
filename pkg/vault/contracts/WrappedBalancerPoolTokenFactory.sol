// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    IWrappedBalancerPoolTokenFactory
} from "@balancer-labs/v3-interfaces/contracts/vault/IWrappedBalancerPoolTokenFactory.sol";

import { WrappedBalancerPoolToken } from "./WrappedBalancerPoolToken.sol";

contract WrappedBalancerPoolTokenFactory is IWrappedBalancerPoolTokenFactory {
    IVault internal immutable vault;
    mapping(address => address) internal _wrappedTokens;

    constructor(IVault vault_) {
        vault = vault_;
    }

    /// @inheritdoc IWrappedBalancerPoolTokenFactory
    function createWrappedToken(address bpt) external returns (address) {
        address wrappedToken = _wrappedTokens[bpt];
        if (wrappedToken != address(0)) {
            revert WrappedBPTAlreadyExists(wrappedToken);
        }

        if (!vault.isPoolInitialized(address(bpt))) {
            revert BalancerPoolTokenNotInitialized();
        }

        string memory name = string(abi.encodePacked("Wrapped ", IERC20Metadata(bpt).name()));
        string memory symbol = string(abi.encodePacked("w", IERC20Metadata(bpt).symbol()));
        wrappedToken = address(new WrappedBalancerPoolToken(vault, IERC20(bpt), name, symbol));

        _wrappedTokens[address(bpt)] = wrappedToken;
        emit WrappedTokenCreated(bpt, wrappedToken);

        return address(wrappedToken);
    }

    /// @inheritdoc IWrappedBalancerPoolTokenFactory
    function getWrappedToken(address bpt) external view returns (address) {
        return _wrappedTokens[bpt];
    }
}
