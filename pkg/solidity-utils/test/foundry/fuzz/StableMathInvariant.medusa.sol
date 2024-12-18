// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { BaseMedusaTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseMedusaTest.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { StableMathMock } from "../../../contracts/test/StableMathMock.sol";

contract StableMathInvariantMedusaTest is BaseMedusaTest {
    uint256 constant MIN_TOKENS = 2;
    uint256 constant MAX_TOKENS = 8;
    uint256 constant DEFAULT_AMP_FACTOR = 200;

    StableMathMock public stableMath;

    int256 internal currentInvariant;
    int256 internal invariantWithDelta;

    constructor() BaseMedusaTest() {
        stableMath = new StableMathMock();
    }

    function optimize_currentInvariant() public view returns (int256) {
        return currentInvariant;
    }

    function optimize_InvariantWithDelta() public view returns (int256) {
        return -invariantWithDelta;
    }

    function property_currentInvariant() public returns (bool) {
        return invariantWithDelta >= currentInvariant;
    }

    function computeInvariants(
        uint256 tokenCount,
        uint256 deltaCount,
        uint256[8] memory indexes,
        uint256[8] memory deltas,
        uint256[8] memory balancesRaw
    ) external {
        tokenCount = bound(tokenCount, MIN_TOKENS, MAX_TOKENS);
        deltaCount = bound(deltaCount, 1, tokenCount);

        uint256[] memory balances = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            balances[i] = bound(balancesRaw[i], 1, type(uint128).max);
            emit Debug("initBalances", balances[i]);
        }

        uint256[] memory newBalances = new uint256[](tokenCount);
        ScalingHelpers.copyToArray(balances, newBalances);

        for (uint256 i = 0; i < deltaCount; i++) {
            uint256 tokenIndex = bound(indexes[i], 0, tokenCount - 1);
            emit Debug("tokenIndex", tokenIndex);

            uint256 delta = bound(deltas[i], 0, type(uint128).max - newBalances[tokenIndex]);
            emit Debug("delta", delta);

            newBalances[tokenIndex] += delta;
        }

        try stableMath.computeInvariant(DEFAULT_AMP_FACTOR, balances, Rounding.ROUND_DOWN) returns (
            uint256 _currentInvariant
        ) {
            try stableMath.computeInvariant(DEFAULT_AMP_FACTOR, newBalances, Rounding.ROUND_DOWN) returns (
                uint256 _invariantWithDelta
            ) {
                currentInvariant = int256(_currentInvariant);
                invariantWithDelta = int256(_invariantWithDelta);
            } catch {}
        } catch {}
    }
}
