// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import { ICowPoolFactory } from "@balancer-labs/v3-interfaces/contracts/pool-cow/ICowPoolFactory.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    TokenConfig,
    PoolRoleAccounts,
    LiquidityManagement
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

import { CowPool } from "./CowPool.sol";

contract CowPoolFactory is ICowPoolFactory, IPoolVersion, BasePoolFactory, Version {
    string internal _poolVersion;
    address internal _trustedCowRouter;

    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion,
        address trustedCowRouter
    ) BasePoolFactory(vault, pauseWindowDuration, type(CowPool).creationCode) Version(factoryVersion) {
        _poolVersion = poolVersion;
        _setTrustedCowRouter(trustedCowRouter);
    }

    /// @inheritdoc IPoolVersion
    function getPoolVersion() external view override returns (string memory) {
        return _poolVersion;
    }

    /// @inheritdoc ICowPoolFactory
    function create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokens,
        uint256[] memory normalizedWeights,
        PoolRoleAccounts memory roleAccounts,
        uint256 swapFeePercentage,
        bytes32 salt
    ) external override returns (address pool) {
        if (roleAccounts.poolCreator != address(0)) {
            revert StandardPoolWithCreator();
        }

        LiquidityManagement memory liquidityManagement = getDefaultLiquidityManagement();
        // CoW AMM Pool needs the donation mechanism to receive surpluses from the solvers.
        liquidityManagement.enableDonation = true;
        // CoW AMM Pool needs to deny unbalanced liquidity so no one can bypass the swap logic and fees.
        liquidityManagement.disableUnbalancedLiquidity = true;

        pool = _create(
            abi.encode(
                WeightedPool.NewPoolParams({
                    name: name,
                    symbol: symbol,
                    numTokens: tokens.length,
                    normalizedWeights: normalizedWeights,
                    version: _poolVersion
                }),
                getVault(),
                _trustedCowRouter
            ),
            salt
        );

        _registerPoolWithVault(
            pool,
            tokens,
            swapFeePercentage,
            false, // not exempt from protocol fees
            roleAccounts,
            pool, // The pool will be its own hook, saving one external contract read
            liquidityManagement
        );
    }

    /// @inheritdoc ICowPoolFactory
    function getTrustedCowRouter() external view override returns (address) {
        return _trustedCowRouter;
    }

    /// @inheritdoc ICowPoolFactory
    function setTrustedCowRouter(address newTrustedCowRouter) external authenticate {
        _setTrustedCowRouter(newTrustedCowRouter);
    }

    function _setTrustedCowRouter(address newTrustedCowRouter) private {
        if (newTrustedCowRouter == address(0)) {
            revert InvalidTrustedCowRouter();
        }

        _trustedCowRouter = newTrustedCowRouter;

        emit CowTrustedRouterChanged(newTrustedCowRouter);
    }
}
