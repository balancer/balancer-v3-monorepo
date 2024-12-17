// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { BaseMedusaTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseMedusaTest.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StableMathMock } from "../../../contracts/test/StableMathMock.sol";

contract StableMathInvariantMedusaTest is BaseMedusaTest {
    uint256 constant MIN_TOKENS = 2;
    uint256 constant MAX_TOKENS = 8;
    uint256 constant DEFAULT_AMP_FACTOR = 200;

    StableMathMock public stableMath;

    uint256 tokenCount;
    uint256[] balances;

    int256 internal initInvariant;
    int256 internal currentInvariant;

    constructor() BaseMedusaTest() {
        stableMath = new StableMathMock();
        currentInvariant = type(int256).max;
    }

    function optimize_currentInvariant() public view returns (int256) {
        return -int256(currentInvariant);
    }

    function property_currentInvariant() public returns (bool) {
        return currentInvariant >= initInvariant;
    }

    function initBalances(uint256 tokenCountRaw, uint256[8] memory balancesRaw) external {
        uint256 prevTokenCount = tokenCount;
        uint256[] memory prevBalances = balances;
        delete balances;

        tokenCount = bound(tokenCountRaw, MIN_TOKENS, MAX_TOKENS);

        for (uint256 i = 0; i < tokenCount; i++) {
            balances.push(bound(balancesRaw[i], 1, type(uint128).max));
            emit Debug("initBalances", balancesRaw[i]);
        }

        try stableMath.computeInvariant(DEFAULT_AMP_FACTOR, balances, Rounding.ROUND_DOWN) returns (uint256 invariant) {
            initInvariant = int256(invariant);
            currentInvariant = initInvariant;
        } catch {
            tokenCount = prevTokenCount;
            balances = prevBalances;
        }
    }

    function addDeltaToBalances(uint256 deltaCount, uint256[8] memory indexes, uint256[8] memory deltas) external {
        deltaCount = bound(deltaCount, 1, tokenCount);

        uint256[] memory newBalances = balances;
        for (uint256 i = 0; i < deltaCount; i++) {
            uint256 tokenIndex = bound(indexes[i], 0, tokenCount - 1);
            uint256 delta = bound(deltas[i], 0, type(uint128).max - newBalances[tokenIndex]);
            newBalances[tokenIndex] += delta;
            emit Debug("delta", delta);
        }

        try stableMath.computeInvariant(DEFAULT_AMP_FACTOR, balances, Rounding.ROUND_DOWN) returns (uint256 invariant) {
            currentInvariant = int256(invariant);
        } catch {}
    }
}
