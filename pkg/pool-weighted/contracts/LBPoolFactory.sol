// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

import { LBPool } from "./LBPool.sol";
import { WeightedPool } from "./WeightedPool.sol";

/**
 * @notice LBPool Factory
 * @dev This is a factory specific to LBPools, allowing only 2 tokens
 */
contract LBPoolFactory is IPoolVersion, BasePoolFactory, Version {
    // solhint-disable not-rely-on-time

    string private _poolVersion;
    address internal immutable TRUSTED_ROUTERS_PROVIDER;
    address internal immutable TRUSTED_ROUTER_TODO_DELETE_ME;

    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion,
        address trustedRoutersProvider,
        address trustedRouterTodoDeleteMe
    ) BasePoolFactory(vault, pauseWindowDuration, type(LBPool).creationCode) Version(factoryVersion) {
        _poolVersion = poolVersion;

        // TODO: validate input address before storing
        TRUSTED_ROUTERS_PROVIDER = trustedRoutersProvider;
        TRUSTED_ROUTER_TODO_DELETE_ME = trustedRouterTodoDeleteMe;
    }

    /// @inheritdoc IPoolVersion
    function getPoolVersion() external view returns (string memory) {
        return _poolVersion;
    }

    /**
     * @notice Deploys a new `LBPool`.
     * @dev Tokens must be sorted for pool registration.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param tokens An array of descriptors for the tokens the pool will manage
     * @param normalizedWeights The pool weights (must add to FixedPoint.ONE)
     * @param swapFeePercentage Initial swap fee percentage
     * @param owner The owner address for pool; sole LP with swapEnable/swapFee change permissions
     * @param salt The salt value that will be passed to create3 deployment
     */
    function create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokens,
        uint256[] memory normalizedWeights,
        uint256 swapFeePercentage,
        address owner,
        bool swapEnabledOnStart,
        bytes32 salt
    ) external returns (address pool) {
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.swapFeeManager = owner;

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
                owner,
                swapEnabledOnStart,
                TRUSTED_ROUTERS_PROVIDER,
                TRUSTED_ROUTER_TODO_DELETE_ME
            ),
            salt
        );

        _registerPoolWithVault(
            pool,
            tokens,
            swapFeePercentage,
            true,
            roleAccounts,
            pool,
            getDefaultLiquidityManagement()
        );
    }
}
