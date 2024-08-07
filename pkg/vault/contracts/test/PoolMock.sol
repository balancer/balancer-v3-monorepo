// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BalancerPoolToken } from "../BalancerPoolToken.sol";

contract PoolMock is IBasePool, IPoolLiquidity, BalancerPoolToken {
    using FixedPoint for uint256;

    uint256 public constant MIN_INIT_BPT = 1e6;

    // Amounts in are multiplied by the multiplier, amounts out are divided by it.
    uint256 private _multiplier = FixedPoint.ONE;

    constructor(IVault vault, string memory name, string memory symbol) BalancerPoolToken(vault, name, symbol) {
        // solhint-previous-line no-empty-blocks
    }

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

    function setMultiplier(uint256 newMultiplier) external {
        _multiplier = newMultiplier;
    }

    function onSwap(PoolSwapParams calldata params) external view override returns (uint256 amountCalculated) {
        return
            params.kind == SwapKind.EXACT_IN
                ? params.amountGivenScaled18.mulDown(_multiplier)
                : params.amountGivenScaled18.divDown(_multiplier);
    }

    function onAddLiquidityCustom(
        address,
        uint256[] memory maxAmountsInScaled18,
        uint256 minBptAmountOut,
        uint256[] memory,
        bytes memory userData
    ) external pure override returns (uint256[] memory, uint256, uint256[] memory, bytes memory) {
        return (maxAmountsInScaled18, minBptAmountOut, new uint256[](maxAmountsInScaled18.length), userData);
    }

    function onRemoveLiquidityCustom(
        address,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        uint256[] memory,
        bytes memory userData
    ) external pure override returns (uint256, uint256[] memory, uint256[] memory, bytes memory) {
        return (maxBptAmountIn, minAmountsOut, new uint256[](minAmountsOut.length), userData);
    }

    /// @dev Even though pools do not handle scaling, we still need this for the tests.
    function getDecimalScalingFactors() external view returns (uint256[] memory scalingFactors) {
        (scalingFactors, ) = _vault.getPoolTokenRates(address(this));
    }

    function getMinimumSwapFeePercentage() external pure override returns (uint256) {
        return 0;
    }

    function getMaximumSwapFeePercentage() external pure override returns (uint256) {
        return FixedPoint.ONE;
    }

    function getMinimumInvariantRatio() external view virtual override returns (uint256) {
        return 0;
    }

    function getMaximumInvariantRatio() external view virtual override returns (uint256) {
        return 1e40; // Something just really big; should always work.
    }
}
