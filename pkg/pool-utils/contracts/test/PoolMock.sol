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

    uint256 public constant MIN_INIT_BPT = 1e10;

    bool public failOnCallback;

    uint256 private immutable _numTokens;

    constructor(
        IVault vault,
        string memory name,
        string memory symbol,
        address factory,
        IERC20[] memory tokens,
        bool registerPool
    ) BasePool(vault, name, symbol, 30 days, 90 days) {
        if (registerPool) {
            vault.registerPool(factory, tokens, PoolConfigBits.wrap(0).toPoolConfig().callbacks);
        }

        _numTokens = tokens.length;
    }

    function onInitialize(
        uint256[] memory amountsIn,
        bytes memory
    ) external view onlyVault returns (uint256[] memory, uint256) {
        return (amountsIn, MIN_INIT_BPT > amountsIn[0] ? MIN_INIT_BPT : amountsIn[0]);
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
        bytes memory,
        uint256[] calldata,
        uint256
    ) external view override returns (bool) {
        return !failOnCallback;
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
        uint256,
        bytes memory,
        uint256[] calldata
    ) external view override returns (bool) {
        return !failOnCallback;
    }

    // Amounts in are multiplied by the multiplier, amounts out are divided by it
    uint256 private _multiplier = FixedPoint.ONE;

    function setFailOnAfterSwap(bool fail) external {
        failOnCallback = fail;
    }

    function setMultiplier(uint256 newMultiplier) external {
        _multiplier = newMultiplier;
    }

    function onAfterSwap(
        IBasePool.AfterSwapParams calldata,
        uint256 amountCalculated
    ) external view override returns (bool success) {
        return amountCalculated > 0 && !failOnCallback;
    }

    function onSwap(IBasePool.SwapParams calldata params) external view override returns (uint256 amountCalculated) {
        return
            params.kind == IVault.SwapKind.GIVEN_IN
                ? params.amountGiven.mulDown(_multiplier)
                : params.amountGiven.divDown(_multiplier);
    }

    function _getTotalTokens() internal view virtual override returns (uint256) {
        return _numTokens;
    }

    function _scalingFactor(IERC20) internal view virtual override returns (uint256) {
        return 1;
    }

    function _scalingFactors() internal view virtual override returns (uint256[] memory) {
        uint256 numTokens = _getTotalTokens();

        uint256[] memory scalingFactors = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            scalingFactors[i] = 1;
        }

        return scalingFactors;
    }
}
