// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import {
    TokenConfig,
    PoolRoleAccounts,
    LiquidityManagement
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

import { StablePool } from "./StablePool.sol";

/**
 * @notice General Stable Pool factory
 * @dev This is the most general factory, which allows up to `StableMath.MAX_STABLE_TOKENS` (5) tokens.
 * Since this limit is less than Vault's maximum of 8 tokens, we need to enforce this at the factory level.
 */
contract StablePoolFactory is IPoolVersion, BasePoolFactory, Version {
    // solhint-disable not-rely-on-time

    string private _poolVersion;

    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion
    ) BasePoolFactory(vault, pauseWindowDuration, type(StablePool).creationCode) Version(factoryVersion) {
        _poolVersion = poolVersion;
    }

    /// @inheritdoc IPoolVersion
    function getPoolVersion() external view returns (string memory) {
        return _poolVersion;
    }

    /**
     * @notice Deploys a new `StablePool`.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param tokens An array of descriptors for the tokens the pool will manage
     * @param amplificationParameter Starting value of the amplificationParameter (see StablePool)
     * @param roleAccounts Addresses the Vault will allow to change certain pool settings
     * @param swapFeePercentage Initial swap fee percentage
     * @param poolHooksContract Contract that implements the hooks for the pool
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
        address poolHooksContract,
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
            poolHooksContract,
            liquidityManagement
        );
    }
}
