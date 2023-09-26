// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PoolConfigBits, PoolConfigLib } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";
import { IVault, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BasePool } from "../BasePool.sol";

contract PoolMock is BasePool {
    using FixedPoint for uint256;

    bool public failOnHook;

    constructor(
        IVault vault,
        string memory name,
        string memory symbol,
        address factory,
        IERC20[] memory tokens,
        bool registerPool
    ) BasePool(vault, name, symbol, tokens, 30 days, 90 days) {
        if (registerPool) {
            vault.registerPool(factory, tokens, PoolConfigBits.wrap(0).toPoolConfig());
        }
    }

    function onInitialize(
        uint256[] memory amountsIn,
        bytes memory
    ) external view onlyVault returns (uint256[] memory, uint256) {
        return (amountsIn, amountsIn[0]);
    }

    function onAddLiquidity(
        address,
        uint256[] memory,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        AddLiquidityKind,
        bytes memory
    ) external pure returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        return (maxAmountsIn, minBptAmountOut);
    }

    function onAfterAddLiquidity(
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes memory,
        uint256[] calldata,
        uint256
    ) external view override returns (bool) {
        return !failOnHook;
    }

    function onRemoveLiquidity(
        address,
        uint256[] memory,
        uint256[] memory minAmountsOut,
        uint256 maxBptAmountIn,
        RemoveLiquidityKind,
        bytes memory
    ) external pure override returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        return (minAmountsOut, maxBptAmountIn);
    }

    function onAfterRemoveLiquidity(
        address,
        uint256[] calldata,
        uint256[] calldata,
        uint256,
        bytes memory,
        uint256[] calldata
    ) external view override returns (bool) {
        return !failOnHook;
    }

    // Amounts in are multiplied by the multiplier, amounts out are divided by it
    uint256 private _multiplier = FixedPoint.ONE;

    function setFailOnAfterSwap(bool fail) external {
        failOnHook = fail;
    }

    function setMultiplier(uint256 newMultiplier) external {
        _multiplier = newMultiplier;
    }

    function onAfterSwap(
        IBasePool.AfterSwapParams calldata params,
        uint256 amountCalculated
    ) external view override returns (bool success) {
        return params.tokenIn != params.tokenOut && amountCalculated > 0 && !failOnHook;
    }

    function onSwap(IBasePool.SwapParams calldata params) external view override returns (uint256 amountCalculated) {
        return
            params.kind == IVault.SwapKind.GIVEN_IN
                ? params.amountGiven.mulDown(_multiplier)
                : params.amountGiven.divDown(_multiplier);
    }

    function _getMaxTokens() internal pure virtual override returns (uint256) {
        return 8;
    }

    function _getTotalTokens() internal view virtual override returns (uint256) {
        return 2;
    }

    function _scalingFactor(IERC20) internal view virtual override returns (uint256) {
        return 1;
    }

    function _scalingFactors() internal view virtual override returns (uint256[] memory) {
        uint256[] memory scalingFactors = new uint256[](2);

        scalingFactors[0] = 1;
        scalingFactors[1] = 1;

        return scalingFactors;
    }
}
