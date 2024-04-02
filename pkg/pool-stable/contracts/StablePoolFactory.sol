// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolFactory } from "@balancer-labs/v3-vault/contracts/factories/BasePoolFactory.sol";

import { StablePool } from "./StablePool.sol";

/**
 * @notice General Stable Pool factory
 * @dev This is the most general factory, which allows up to four tokens.
 */
contract StablePoolFactory is BasePoolFactory {
    // solhint-disable not-rely-on-time

    constructor(
        IVault vault,
        uint256 pauseWindowDuration
    ) BasePoolFactory(vault, pauseWindowDuration, type(StablePool).creationCode) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Deploys a new `StablePool`.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param tokens An array of descriptors for the tokens the pool will manage
     * @param amplificationParameter The starting Amplification Parameter
     * @param salt The salt value that will be passed to create3 deployment
     */
    function create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokens,
        uint256 amplificationParameter,
        uint256 swapFeePercentage,
        bytes32 salt
    ) external returns (address pool) {
        pool = _create(
            abi.encode(
                StablePool.NewPoolParams({
                    name: name,
                    symbol: symbol,
                    amplificationParameter: amplificationParameter
                }),
                getVault()
            ),
            salt
        );

        getVault().registerPool(
            pool,
            tokens,
            swapFeePercentage,
            getNewPoolPauseWindowEndTime(),
            PoolRoleAccounts({ pauseManager: address(0), swapFeeManager: address(0) }),
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
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: false,
                enableRemoveLiquidityCustom: false
            })
        );

        _registerPoolWithFactory(pool);
    }
}
