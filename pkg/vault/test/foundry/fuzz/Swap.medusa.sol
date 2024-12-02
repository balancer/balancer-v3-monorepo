// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { BasePoolMath } from "../../../contracts/BasePoolMath.sol";
import { BalancerPoolToken } from "../../../contracts/BalancerPoolToken.sol";

import "../utils/BaseMedusaTest.sol";

abstract contract SwapMedusaTest is BaseMedusaTest {
    int256 internal invariantBefore = 0;
    int256 internal currentInvariant = 0;

    constructor() BaseMedusaTest() {
        currentInvariant = computeInvariant();
        invariantBefore = currentInvariant;

        vault.manuallySetSwapFee(address(pool), 0);
    }

    function optimize_currentInvariant() public view returns (int256) {
        return currentInvariant;
    }

    function property_currentInvariant_never_increases() public returns (bool) {
        return assertInvariant();
    }

    function assertInvariant() internal returns (bool) {
        updateInvariant();
        return currentInvariant <= invariantBefore;
    }

    function computeInvariant() internal view returns (int256) {
        (, , , uint256[] memory lastBalancesLiveScaled18) = vault.getPoolTokenInfo(address(pool));
        return int256(pool.computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_UP));
    }

    function computeSwapExactIn(uint256 tokenIndexIn, uint256 tokenIndexOut, uint256 exactAmountIn) public {
        tokenIndexIn = boundTokenIndex(tokenIndexIn);
        tokenIndexOut = boundTokenIndex(tokenIndexOut);

        if (tokenIndexIn == tokenIndexOut) {
            tokenIndexIn = 0;
            tokenIndexOut = 1;
        }

        exactAmountIn = boundSwapAmount(exactAmountIn, tokenIndexIn);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        medusa.prank(alice);
        router.swapSingleTokenExactIn(
            address(pool),
            tokens[tokenIndexIn],
            tokens[tokenIndexOut],
            exactAmountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
        updateInvariant();
    }

    function updateInvariant() internal {
        invariantBefore = currentInvariant;
        currentInvariant = computeInvariant();

        emit Debug("invariant before", uint256(invariantBefore));
        emit Debug("current invariant", uint256(currentInvariant));
    }

    function boundTokenIndex(uint256 tokenIndex) internal view returns (uint256 boundedIndex) {
        uint256 len = vault.getPoolTokens(address(pool)).length;
        boundedIndex = bound(tokenIndex, 0, len - 1);
    }

    function boundSwapAmount(
        uint256 tokenAmountIn,
        uint256 tokenIndex
    ) internal view returns (uint256 boundedAmountIn) {
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));
        boundedAmountIn = bound(tokenAmountIn, 0, MAX_BALANCE - balancesRaw[tokenIndex]);
    }
}
