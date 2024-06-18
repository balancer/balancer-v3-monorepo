// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { BalancerPoolToken } from "../BalancerPoolToken.sol";

contract PoolMockCommon is IBasePool, BalancerPoolToken {
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;

    uint256 public constant MIN_INIT_BPT = 1e6;

    // Amounts in are multiplied by the multiplier, amounts out are divided by it
    uint256 private _multiplier = FixedPoint.ONE;

    constructor(IVault vault, string memory name, string memory symbol) BalancerPoolToken(vault, name, symbol) {
        // solhint-previous-line no-empty-blocks
    }

    /// @inheritdoc IBasePool
    function computeInvariant(uint256[] memory balances) public pure returns (uint256) {
        // inv = x + y
        uint256 invariant;
        for (uint256 i = 0; i < balances.length; ++i) {
            invariant += balances[i];
        }
        return invariant;
    }

    /// @inheritdoc IBasePool
    function computeBalance(
        uint256[] memory balances,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external pure returns (uint256 newBalance) {
        // inv = x + y
        uint256 invariant = computeInvariant(balances);
        return (balances[tokenInIndex] + invariant.mulDown(invariantRatio)) - invariant;
    }

    /// @inheritdoc IBasePool
    function onSwap(
        IBasePool.PoolSwapParams calldata params
    ) external view override returns (uint256 amountCalculated) {
        return
            params.kind == SwapKind.EXACT_IN
                ? params.amountGivenScaled18.mulDown(_multiplier)
                : params.amountGivenScaled18.divDown(_multiplier);
    }

    /// @inheritdoc ISwapFeePercentageBounds
    function getMinimumSwapFeePercentage() external pure returns (uint256) {
        return 0;
    }

    /// @inheritdoc ISwapFeePercentageBounds
    function getMaximumSwapFeePercentage() external pure returns (uint256) {
        return FixedPoint.ONE;
    }

    function setMultiplier(uint256 newMultiplier) external {
        _multiplier = newMultiplier;
    }

    /// @dev Even though pools do not handle scaling, we still need this for the tests.
    function getDecimalScalingFactors() external view returns (uint256[] memory scalingFactors) {
        (scalingFactors, ) = _vault.getPoolTokenRates(address(this));
    }
}
