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

import { StablePool } from "./StablePool.sol";

/**
 * @notice Unpausable Stable Pool factory.
 * @dev This is a special purpose pool factory that creates Stable Pools without pause functionality. By design,
 * pause functionality in V3 is handled by the Vault, and there is no way for a V3 pool to "opt out" of the core
 * pause mechanism. However, since the pause window duration is configurable (with no lower limit), it is possible
 * to deploy pools with a pause window duration of 0 seconds, effectively making them unpausable.
 */
contract UnpausableStablePoolFactory is IPoolVersion, BasePoolFactory, Version {
    string private _poolVersion;

    /// @dev Hard-code the pause duration to 0 seconds, making pools created by this factory effectively unpausable.
    constructor(
        IVault vault,
        string memory factoryVersion,
        string memory poolVersion
    ) BasePoolFactory(vault, 0, type(StablePool).creationCode) Version(factoryVersion) {
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
     * @param salt The salt value that will be passed to deployment
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
