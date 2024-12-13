// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";

import { GyroECLPPool } from "./GyroECLPPool.sol";

/**
 * @notice Gyro E-CLP Pool factory.
 * @dev This is the pool factory for Gyro E-CLP pools, which supports two tokens only.
 */
contract GyroECLPPoolFactory is BasePoolFactory {
    // solhint-disable not-rely-on-time

    /// @notice ECLP pools support 2 tokens only.
    error SupportsOnlyTwoTokens();

    constructor(
        IVault vault,
        uint32 pauseWindowDuration
    ) BasePoolFactory(vault, pauseWindowDuration, type(GyroECLPPool).creationCode) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Deploys a new `GyroECLPPool`.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param tokens An array of descriptors for the tokens the pool will manage
     * @param eclpParams parameters to configure the pool
     * @param derivedEclpParams parameters with 38 decimals precision, to configure the pool
     * @param roleAccounts Addresses the Vault will allow to change certain pool settings
     * @param swapFeePercentage Initial swap fee percentage
     * @param poolHooksContract Contract that implements the hooks for the pool
     * @param salt The salt value that will be passed to create3 deployment
     */
    function create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokens,
        IGyroECLPPool.EclpParams memory eclpParams,
        IGyroECLPPool.DerivedEclpParams memory derivedEclpParams,
        PoolRoleAccounts memory roleAccounts,
        uint256 swapFeePercentage,
        address poolHooksContract,
        bytes32 salt
    ) external returns (address pool) {
        require(tokens.length == 2, SupportsOnlyTwoTokens());
        require(roleAccounts.poolCreator == address(0), StandardPoolWithCreator());

        pool = _create(
            abi.encode(
                IGyroECLPPool.GyroECLPPoolParams({
                    name: name,
                    symbol: symbol,
                    eclpParams: eclpParams,
                    derivedEclpParams: derivedEclpParams
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
            getDefaultLiquidityManagement()
        );

        _registerPoolWithFactory(pool);
    }
}
