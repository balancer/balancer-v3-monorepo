// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolFactory } from "@balancer-labs/v3-vault/contracts/factories/BasePoolFactory.sol";

import { WeightedPool } from "./WeightedPool.sol";

/**
 * @notice General Weighted Pool factory
 * @dev This is the most general factory, which allows up to four tokens and arbitrary weights.
 */
contract WeightedPoolFactory is BasePoolFactory {
    // solhint-disable not-rely-on-time

    constructor(
        IVault vault,
        uint256 pauseWindowDuration
    ) BasePoolFactory(vault, pauseWindowDuration, type(WeightedPool).creationCode) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Deploys a new `WeightedPool`.
     * @param params The basic pool parameters required for Vault registration. See BasePoolFactory.
     * @param normalizedWeights The pool weights (must add to FixedPoint.ONE)
     * @param salt The salt value that will be passed to create3 deployment
     */
    function create(
        BasePoolParams memory params,
        uint256[] memory normalizedWeights,
        bytes32 salt
    ) external returns (address pool) {
        pool = _create(
            abi.encode(
                WeightedPool.NewPoolParams({
                    name: params.name,
                    symbol: params.symbol,
                    numTokens: params.tokens.length,
                    normalizedWeights: normalizedWeights
                }),
                getVault()
            ),
            salt
        );

        _registerPoolWithVault(pool, params);
    }
}
