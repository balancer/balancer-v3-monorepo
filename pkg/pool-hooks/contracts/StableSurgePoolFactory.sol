// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    TokenConfig,
    PoolRoleAccounts,
    LiquidityManagement
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { StablePool } from "@balancer-labs/v3-pool-stable/contracts/StablePool.sol";

import { StableSurgeHook } from "./StableSurgeHook.sol";

/// @notice Stable Pool factory that deploys a standard StablePool with a StableSurgeHook.
contract StableSurgePoolFactory is IPoolVersion, BasePoolFactory, Version {
    address private immutable _stableSurgeHook;

    string private _poolVersion;

    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        uint256 defaultMaxSurgeFeePercentage,
        uint256 defaultSurgeThresholdPercentage,
        string memory factoryVersion,
        string memory poolVersion
    ) BasePoolFactory(vault, pauseWindowDuration, type(StablePool).creationCode) Version(factoryVersion) {
        _poolVersion = poolVersion;
        _stableSurgeHook = address(
            new StableSurgeHook(vault, defaultMaxSurgeFeePercentage, defaultSurgeThresholdPercentage)
        );
    }

    /// @inheritdoc IPoolVersion
    function getPoolVersion() external view returns (string memory) {
        return _poolVersion;
    }

    /**
     * @notice Getter for the internally deployed stable surge hook contract.
     * @dev This hook will be registered to every pool created by this factory.
     * @return address stableSurgeHook Address of the deployed StableSurgeHook
     */
    function getStableSurgeHook() external view returns (address) {
        return _stableSurgeHook;
    }

    /**
     * @notice Deploys a new `StablePool`.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param tokens An array of descriptors for the tokens the pool will manage
     * @param amplificationParameter Starting value of the amplificationParameter (see StablePool)
     * @param roleAccounts Addresses the Vault will allow to change certain pool settings
     * @param swapFeePercentage Initial swap fee percentage
     * @param enableDonation If true, the pool will support the donation add liquidity mechanism
     * @param disableUnbalancedLiquidity If true, only proportional add and remove liquidity are accepted
     * @param salt The salt value that will be passed to create3 deployment
     */
    function create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokens,
        uint256 amplificationParameter,
        PoolRoleAccounts memory roleAccounts,
        uint256 swapFeePercentage,
        bool enableDonation,
        bool disableUnbalancedLiquidity,
        bytes32 salt
    ) external returns (address pool) {
        if (roleAccounts.poolCreator != address(0)) {
            revert StandardPoolWithCreator();
        }

        // As the Stable Pool deployment does not know about the tokens, and the registration doesn't know about the
        // pool type, we enforce the token limit at the factory level.
        if (tokens.length > StableMath.MAX_STABLE_TOKENS) {
            revert IVaultErrors.MaxTokens();
        }

        LiquidityManagement memory liquidityManagement = getDefaultLiquidityManagement();
        liquidityManagement.enableDonation = enableDonation;
        liquidityManagement.disableUnbalancedLiquidity = disableUnbalancedLiquidity;

        pool = _create(
            abi.encode(
                StablePool.NewPoolParams({
                    name: name,
                    symbol: symbol,
                    amplificationParameter: amplificationParameter,
                    version: _poolVersion
                }),
                getVault()
            ),
            salt
        );

        _registerPoolWithVault(
            pool,
            tokens,
            swapFeePercentage,
            false, // not exempt from protocol fees
            roleAccounts,
            _stableSurgeHook,
            liquidityManagement
        );
    }
}
