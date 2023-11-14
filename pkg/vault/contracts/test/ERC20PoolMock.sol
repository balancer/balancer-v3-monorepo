// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ERC20PoolToken } from "@balancer-labs/v3-solidity-utils/contracts/token/ERC20PoolToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolConfigBits, PoolConfigLib } from "../lib/PoolConfigLib.sol";

import { PoolFactoryMock } from "./PoolFactoryMock.sol";

contract ERC20PoolMock is ERC20PoolToken, IBasePool {
    using FixedPoint for uint256;

    uint256 public constant MIN_INIT_BPT = 1e6;

    bool public failOnAfterSwapCallback;
    bool public failOnBeforeAddLiquidity;
    bool public failOnAfterAddLiquidity;
    bool public failOnBeforeRemoveLiquidity;
    bool public failOnAfterRemoveLiquidity;

    // Amounts in are multiplied by the multiplier, amounts out are divided by it
    uint256 private _multiplier = FixedPoint.ONE;

    constructor(
        IVault vault,
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        bool registerPool
    ) ERC20PoolToken(vault, name, symbol) {
        if (registerPool) {
            PoolFactoryMock factory = new PoolFactoryMock(vault, 365 days, 30 days);

            factory.registerPool(
                address(this),
                tokens,
                PoolConfigBits.wrap(0).toPoolConfig().callbacks,
                PoolConfigBits.wrap(bytes32(type(uint256).max)).toPoolConfig().liquidityManagement
            );
        }
    }

    function onInitialize(uint256[] memory exactAmountsIn, bytes memory) external pure override returns (uint256) {
        return (MIN_INIT_BPT > exactAmountsIn[0] ? MIN_INIT_BPT : exactAmountsIn[0]);
    }

    function setFailOnAfterSwapCallback(bool fail) external {
        failOnAfterSwapCallback = fail;
    }

    function setFailOnBeforeAddLiquidityCallback(bool fail) external {
        failOnBeforeAddLiquidity = fail;
    }

    function setFailOnAfterAddLiquidityCallback(bool fail) external {
        failOnAfterAddLiquidity = fail;
    }

    function setFailOnBeforeRemoveLiquidityCallback(bool fail) external {
        failOnBeforeRemoveLiquidity = fail;
    }

    function setFailOnAfterRemoveLiquidityCallback(bool fail) external {
        failOnAfterRemoveLiquidity = fail;
    }

    function setMultiplier(uint256 newMultiplier) external {
        _multiplier = newMultiplier;
    }

    function onAfterSwap(
        IBasePool.AfterSwapParams calldata params,
        uint256 amountCalculated
    ) external view override returns (bool success) {
        return params.tokenIn != params.tokenOut && amountCalculated > 0 && !failOnAfterSwapCallback;
    }

    function onSwap(IBasePool.SwapParams calldata params) external view override returns (uint256 amountCalculated) {
        return
            params.kind == IVault.SwapKind.GIVEN_IN
                ? params.amountGiven.mulDown(_multiplier)
                : params.amountGiven.divDown(_multiplier);
    }

    // Liquidity lifecycle callbacks

    function onBeforeAddLiquidity(
        address,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external view override returns (bool) {
        return !failOnBeforeAddLiquidity;
    }

    function onBeforeRemoveLiquidity(
        address,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external view override returns (bool) {
        return !failOnBeforeRemoveLiquidity;
    }

    function onAfterAddLiquidity(
        address,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external view override returns (bool) {
        return !failOnAfterAddLiquidity;
    }

    function onAfterRemoveLiquidity(
        address,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external view override returns (bool) {
        return !failOnAfterRemoveLiquidity;
    }

    function onAddLiquidityUnbalanced(
        address,
        uint256[] memory exactAmountsIn,
        uint256[] memory
    ) external pure override returns (uint256 bptAmountOut) {
        bptAmountOut = exactAmountsIn[0];
    }

    function onAddLiquiditySingleTokenExactOut(
        address sender,
        uint256 tokenInIndex,
        uint256,
        uint256[] memory
    ) external view override returns (uint256 amountIn) {
        (IERC20[] memory tokens, ) = getVault().getPoolTokens(address(this));
        return tokens[tokenInIndex].balanceOf(sender);
    }

    function onAddLiquidityCustom(
        address,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        uint256[] memory,
        bytes memory userData
    ) external pure override returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) {
        amountsIn = maxAmountsIn;
        bptAmountOut = minBptAmountOut;
        returnData = userData;
    }

    function onRemoveLiquiditySingleTokenExactIn(
        address,
        uint256 tokenOutIndex,
        uint256,
        uint256[] memory currentBalances
    ) external pure override returns (uint256 amountOut) {
        amountOut = currentBalances[tokenOutIndex];
    }

    function onRemoveLiquiditySingleTokenExactOut(
        address sender,
        uint256,
        uint256,
        uint256[] memory
    ) external view override returns (uint256 bptAmountIn) {
        return balanceOf(sender);
    }

    function onRemoveLiquidityCustom(
        address,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        uint256[] memory,
        bytes memory userData
    ) external pure override returns (uint256, uint256[] memory, bytes memory) {
        return (maxBptAmountIn, minAmountsOut, userData);
    }

    function getPoolTokens() external view returns (IERC20[] memory tokens, uint256[] memory balances) {
        return getVault().getPoolTokens(address(this));
    }
}
