// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolFactory } from "@balancer-labs/v3-vault/contracts/factories/BasePoolFactory.sol";

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
        uint256 pauseWindowDuration
    ) BasePoolFactory(vault, pauseWindowDuration, type(Gyro2CLPPool).creationCode) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Deploys a new `StablePool`.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param tokens An array of descriptors for the tokens the pool will manage
     * @param sqrtAlpha square root of first element in price range
     * @param sqrtBeta square root of last element in price range
     * @param salt The salt value that will be passed to create3 deployment
     */
    function create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokens,
        uint256 sqrtAlpha,
        uint256 sqrtBeta,
        bytes32 salt
    ) external returns (address pool) {
        if (tokens.length != 2) {
            revert SupportsOnlyTwoTokens();
        }

        pool = _create(
            abi.encode(
                Gyro2CLPPool.GyroParams({
                    name: name,
                    symbol: symbol,
                    sqrtAlpha: sqrtAlpha,
                    sqrtBeta: sqrtBeta
                }),
                getVault()
            ),
            salt
        );

        getVault().registerPool(
            pool,
            tokens,
            getNewPoolPauseWindowEndTime(),
            address(0), // no pause manager
            PoolHooks({
                shouldCallBeforeInitialize: false,
                shouldCallAfterInitialize: false,
                shouldCallBeforeAddLiquidity: false,
                shouldCallAfterAddLiquidity: false,
                shouldCallBeforeRemoveLiquidity: false,
                shouldCallAfterRemoveLiquidity: false,
                shouldCallBeforeSwap: false,
                shouldCallAfterSwap: false
            }),
            LiquidityManagement({ supportsAddLiquidityCustom: false, supportsRemoveLiquidityCustom: false })
        );

        _registerPoolWithFactory(pool);
    }
}
