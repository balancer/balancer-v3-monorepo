// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IGyro2CLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyro2CLPPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";

import { Gyro2CLPPool } from "./Gyro2CLPPool.sol";

/**
 * @notice Gyro 2CLP Pool factory
 * @dev This is the most general factory, which allows two tokens.
 */
contract Gyro2CLPPoolFactory is BasePoolFactory {
    // solhint-disable not-rely-on-time

    error SupportsOnlyTwoTokens();

    constructor(
        IVault vault,
        uint32 pauseWindowDuration
    ) BasePoolFactory(vault, pauseWindowDuration, type(Gyro2CLPPool).creationCode) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Deploys a new `Gyro2CLPPool`.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param tokens An array of descriptors for the tokens the pool will manage
     * @param sqrtAlpha square root of first element in price range
     * @param sqrtBeta square root of last element in price range
     * @param roleAccounts Addresses the Vault will allow to change certain pool settings
     * @param swapFeePercentage Initial swap fee percentage
     * @param poolHooksContract Contract that implements the hooks for the pool
     * @param salt The salt value that will be passed to create3 deployment
     */
    function create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokens,
        uint256 sqrtAlpha,
        uint256 sqrtBeta,
        PoolRoleAccounts memory roleAccounts,
        uint256 swapFeePercentage,
        address poolHooksContract,
        bytes32 salt
    ) external returns (address pool) {
        if (tokens.length != 2) {
            revert SupportsOnlyTwoTokens();
        }

        pool = _create(
            abi.encode(
                IGyro2CLPPool.GyroParams({ name: name, symbol: symbol, sqrtAlpha: sqrtAlpha, sqrtBeta: sqrtBeta }),
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
