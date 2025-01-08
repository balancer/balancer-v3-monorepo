// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { TokenConfig, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

import { WeightedPool } from "../WeightedPool.sol";
import { LBPool } from "./LBPool.sol";

/**
 * @notice LBPool Factory.
 * @dev This is a factory specific to LBPools, allowing only 2 tokens.
 */
contract LBPoolFactory is IPoolVersion, ReentrancyGuardTransient, BasePoolFactory, Version {
    // LBPs are constrained to two tokens.
    uint256 private constant _NUM_TOKENS = 2;

    string private _poolVersion;

    address internal immutable _trustedRouter;

    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion,
        address trustedRouter
    ) BasePoolFactory(vault, pauseWindowDuration, type(LBPool).creationCode) Version(factoryVersion) {
        _poolVersion = poolVersion;

        // LBPools are deployed with a router known to reliably report the originating address on operations.
        _trustedRouter = trustedRouter;
    }

    /// @inheritdoc IPoolVersion
    function getPoolVersion() external view returns (string memory) {
        return _poolVersion;
    }

    /// @notice Returns trusted router, which is the gateway to add liquidity to the pool.
    function getTrustedRouter() external view returns (address) {
        return _trustedRouter;
    }

    /**
     * @notice Deploys a new `LBPool`.
     * @dev Tokens must be sorted for pool registration.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param tokenConfig An array of descriptors for the tokens the pool will manage
     * @param normalizedWeights The pool weights (must add to FixedPoint.ONE)
     * @param swapFeePercentage Initial swap fee percentage
     * @param owner The owner address for pool; sole LP with swapEnable/swapFee change permissions
     * @param salt The salt value that will be passed to create3 deployment
     */
    function create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokenConfig,
        uint256[] memory normalizedWeights,
        uint256 swapFeePercentage,
        address owner,
        bool swapEnabledOnStart,
        bytes32 salt
    ) external nonReentrant returns (address pool) {
        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, tokenConfig.length);
        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, normalizedWeights.length);

        PoolRoleAccounts memory roleAccounts;
        // It's not necessary to set the pauseManager, as the owner can already effectively pause the pool by disabling
        // swaps. There is also no poolCreator, as the owner is already using this to earn revenue directly.
        roleAccounts.swapFeeManager = owner;

        pool = _create(
            abi.encode(
                WeightedPool.NewPoolParams({
                    name: name,
                    symbol: symbol,
                    numTokens: tokenConfig.length,
                    normalizedWeights: normalizedWeights,
                    version: _poolVersion
                }),
                getVault(),
                owner,
                swapEnabledOnStart,
                _trustedRouter
            ),
            salt
        );

        _registerPoolWithVault(
            pool,
            tokenConfig,
            swapFeePercentage,
            false, // not exempt from protocol fees
            roleAccounts,
            pool, // register the pool itself as the hook contract
            getDefaultLiquidityManagement()
        );
    }
}
