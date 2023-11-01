// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { ERC20PoolToken } from "@balancer-labs/v3-solidity-utils/contracts/token/ERC20PoolToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolConfigBits, PoolConfigLib } from "../lib/PoolConfigLib.sol";

contract ERC20PoolMock is ERC20PoolToken, IBasePool {
    using FixedPoint for uint256;

    IVault private immutable _vault;

    bool public failOnCallback;

    constructor(
        IVault vault,
        string memory name,
        string memory symbol,
        address factory,
        IERC20[] memory tokens,
        bool registerPool
    ) ERC20PoolToken(vault, name, symbol) {
        _vault = vault;

        if (registerPool) {
            vault.registerPool(
                factory,
                tokens,
                PoolConfigBits.wrap(0).toPoolConfig().callbacks,
                PoolConfigBits.wrap(bytes32(type(uint256).max)).toPoolConfig().liquidityManagement
            );
        }
    }

    function onInitialize(
        uint256[] memory amountsIn,
        bytes memory
    ) external pure override returns (uint256[] memory, uint256) {
        return (amountsIn, amountsIn[0]);
    }

    function onAfterAddLiquidity(
        address,
        uint256[] calldata,
        bytes memory,
        uint256[] calldata,
        uint256
    ) external view returns (bool) {
        return !failOnCallback;
    }

    function onAfterRemoveLiquidity(
        address,
        uint256[] calldata,
        uint256,
        bytes memory,
        uint256[] calldata
    ) external view returns (bool) {
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
        IBasePool.AfterSwapParams calldata params,
        uint256 amountCalculated
    ) external view override returns (bool success) {
        return params.tokenIn != params.tokenOut && amountCalculated > 0 && !failOnCallback;
    }

    function onSwap(IBasePool.SwapParams calldata params) external view override returns (uint256 amountCalculated) {
        return
            params.kind == IVault.SwapKind.GIVEN_IN
                ? params.amountGiven.mulDown(_multiplier)
                : params.amountGiven.divDown(_multiplier);
    }

    function onBeforeAddLiquidity(
        uint256[] memory,
        uint256[] memory,
        uint256,
        bytes memory
    ) external pure override returns (bool) {
        return true;
    }

    function onBeforeRemoveLiquidity(
        uint256[] memory,
        uint256[] memory,
        uint256,
        bytes memory
    ) external pure override returns (bool) {
        return true;
    }

    function onAddLiquidityUnbalanced(
        address,
        uint256[] memory exactAmountsIn,
        uint256[] memory
    ) external pure override returns (uint256 bptAmountOut) {
        bptAmountOut = exactAmountsIn[0];
    }

    function onAddLiquiditySingleTokenExactOut(
        address,
        uint256,
        uint256 exactBptAmountOut,
        uint256[] memory
    ) external pure override returns (uint256 amountIn) {
        return exactBptAmountOut;
    }

    function onAddLiquidityCustom(
        address,
        uint256[] memory,
        uint256,
        bytes memory userData,
        uint256[] memory currentBalances
    ) external pure override returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) {
        amountsIn = currentBalances;
        bptAmountOut = currentBalances[0];
        returnData = userData;
    }

    function onRemoveLiquiditySingleTokenExactIn(
        address sender,
        uint256 tokenIndex,
        uint256 exactBptAmountIn,
        uint256[] memory currentBalances
    ) external returns (uint256 amountOut) {}

    function onRemoveLiquiditySingleTokenExactOut(
        address sender,
        uint256 tokenOutIndex,
        uint256 exactAmountOut,
        uint256[] memory currentBalances
    ) external returns (uint256 bptAmountIn) {}

    function onRemoveLiquidityCustom(
        address sender,
        uint256[] memory,
        uint256,
        bytes memory userData,
        uint256[] memory currentBalances
    ) external returns (uint256[] memory amountsOut, uint256 bptAmountIn, bytes memory returnData) {}

    function getPoolTokens() external view returns (IERC20[] memory tokens, uint256[] memory balances) {
        return _vault.getPoolTokens(address(this));
    }
}
