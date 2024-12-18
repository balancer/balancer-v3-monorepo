// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";

import { PriceImpactHelper } from "../PriceImpactHelper.sol";

contract PriceImpactHelperMock is PriceImpactHelper {
    constructor(IVault vault, IRouter router) PriceImpactHelper(vault, router) {}

    function queryAddLiquidityUnbalancedForTokenDeltas(
        address pool,
        uint256 tokenIndex,
        int256[] memory deltas,
        address sender
    ) external returns (int256 deltaBPT) {
        return _queryAddLiquidityUnbalancedForTokenDeltas(pool, tokenIndex, deltas, sender);
    }

    function zeroOutDeltas(
        address pool,
        int256[] memory deltas,
        int256[] memory deltaBPTs,
        address sender
    ) external returns (uint256) {
        return _zeroOutDeltas(pool, deltas, deltaBPTs, sender);
    }

    function minPositiveIndex(int256[] memory array) external pure returns (uint256) {
        return _minPositiveIndex(array);
    }

    function maxNegativeIndex(int256[] memory array) external pure returns (uint256) {
        return _maxNegativeIndex(array);
    }
}
