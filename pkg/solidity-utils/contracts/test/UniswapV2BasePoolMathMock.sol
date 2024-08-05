// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../math/FixedPoint.sol";
import "./BasePoolMathMock.sol";

// Mock UniswapV2 to test rounding in BasePoolMath for consistency with other implementations.
// This example is from the Balancer V3 documentation.
contract UniswapV2BasePoolMathMock is BasePoolMathMock {
    using FixedPoint for uint256;

    function computeInvariant(uint256[] memory balancesLiveScaled18) public pure override returns (uint256 invariant) {
        require(balancesLiveScaled18.length == 2, "UniswapV2BasePoolMathMock: Only 2 tokens are supported");

        // Expected to work with 2 tokens only.
        invariant = balancesLiveScaled18[0].mulDown(balancesLiveScaled18[1]);
        // Scale the invariant to 1e18.
        invariant = Math.sqrt(invariant) * 1e9;
    }

    /**
     * @dev Computes the new balance of a token after an operation, given the invariant growth ratio and all other
     * balances.
     * @param balancesLiveScaled18 Current live balances (adjusted for decimals, rates, etc.)
     * @param tokenInIndex The index of the token we're computing the balance for, in token registration order
     * @param invariantRatio The ratio of the new invariant (after an operation) to the old
     * @return newBalance The new balance of the selected token, after the operation
     */
    function computeBalance(
        uint256[] memory balancesLiveScaled18,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external pure override returns (uint256 newBalance) {
        require(balancesLiveScaled18.length == 2, "UniswapV2BasePoolMathMock: Only 2 tokens are supported");

        uint256 otherTokenIndex = tokenInIndex == 0 ? 1 : 0;

        uint256 newInvariant = computeInvariant(balancesLiveScaled18).mulDown(invariantRatio);

        newBalance = ((newInvariant * newInvariant) / balancesLiveScaled18[otherTokenIndex]);
    }
}
