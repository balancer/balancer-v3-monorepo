// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import { TokenConfig, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

import { WeightedPool } from "./WeightedPool.sol";
import { LBPool } from "./LBPool.sol";

/**
 * @notice LBPool Factory.
 * @dev This is a factory specific to LBPools, allowing only 2 tokens.
 */
contract LBPoolFactory is IPoolVersion, BasePoolFactory, Version {
    string private _poolVersion;

    // solhint-disable-next-line var-name-mixedcase
    address internal immutable _TRUSTED_ROUTER;

    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion,
        address trustedRouter
    ) BasePoolFactory(vault, pauseWindowDuration, type(LBPool).creationCode) Version(factoryVersion) {
        _poolVersion = poolVersion;

        // LBPools are deployed with a router known to reliably report the originating address on operations.
        _TRUSTED_ROUTER = trustedRouter;
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
        // It's not necessary to set the pauseManager, as the owner can already effectively pause the pool
        // by disabling swaps.
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
                _TRUSTED_ROUTER
            ),
            salt
        );

        _registerPoolWithVault(
            pool,
            tokens,
            swapFeePercentage,
            true, // protocol fee exempt
            roleAccounts,
            pool,
            getDefaultLiquidityManagement()
        );
    }
}
