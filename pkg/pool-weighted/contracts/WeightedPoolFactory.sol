// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import "@balancer-labs/v3-vault/contracts/factories/BasePoolFactory.sol";

import "./WeightedPool.sol";

/**
 * @notice General Weighted Pool factory
 * @dev This is the most general factory, which allows up to four tokens and arbitrary weights.
 */
contract WeightedPoolFactory is BasePoolFactory {
    constructor(
        IVault vault,
        uint256 initialPauseWindowDuration,
        uint256 bufferPeriodDuration
    ) BasePoolFactory(vault, initialPauseWindowDuration, bufferPeriodDuration) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @dev Deploys a new `WeightedPool`.
     */
    function create(
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        uint256[] memory normalizedWeights,
        bytes32 salt
    ) external returns (address pool) {
        // Passing the salt argument causes the contract to be deployed with create2.
        pool = address(
            new WeightedPool{ salt: salt }(
                WeightedPool.NewPoolParams({
                    name: name,
                    symbol: symbol,
                    tokens: tokens,
                    normalizedWeights: normalizedWeights
                }),
                getVault()
            )
        );

        (uint256 pauseWindowDuration, uint256 bufferPeriodDuration) = getPauseConfiguration();

        getVault().registerPool(
            pool,
            tokens,
            pauseWindowDuration,
            bufferPeriodDuration,
            PoolCallbacks({
                shouldCallAfterAddLiquidity: false,
                shouldCallAfterRemoveLiquidity: false,
                shouldCallAfterSwap: false
            })
        );

        _registerPoolWithFactory(pool);
    }
}
