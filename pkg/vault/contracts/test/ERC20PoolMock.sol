// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ERC20FacadeToken } from "../ERC20FacadeToken.sol";

contract ERC20PoolMock is ERC20FacadeToken, IBasePool {
    using FixedPoint for uint256;

    IVault private immutable _vault;

    constructor(
        IVault vault,
        string memory name,
        string memory symbol,
        address factory,
        IERC20[] memory tokens,
        bool registerPool
    ) ERC20FacadeToken(vault, name, symbol) {
        _vault = vault;

        if (registerPool) {
            vault.registerPool(factory, tokens);
        }
    }

    function onAddLiquidity(
        address,
        uint256[] memory,
        uint256[] memory maxAmountsIn,
        bytes memory
    ) external pure returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        return (maxAmountsIn, maxAmountsIn[0]);
    }

    function onRemoveLiquidity(
        address,
        uint256[] memory,
        uint256[] memory minAmountsOut,
        uint256,
        bytes memory
    ) external pure returns (uint256[] memory amountsOut) {
        return minAmountsOut;
    }

    // Amounts in are multiplied by the multiplier, amounts out are divided by it
    uint256 private _multiplier = FixedPoint.ONE;

    function setMultiplier(uint256 newMultiplier) external {
        _multiplier = newMultiplier;
    }

    function onSwap(IBasePool.SwapParams calldata params) external view override returns (uint256 amountCalculated) {
        return
            params.kind == IVault.SwapKind.GIVEN_IN
                ? params.amountGiven.mulDown(_multiplier)
                : params.amountGiven.divDown(_multiplier);
    }

    function supportsAddLiquidityProportional() external pure override returns (bool) {
        return true;
    }

    function supportsRemoveLiquidityProportional() external pure override returns (bool){
        return true;
    }

    function onBeforeAdd(uint256[] memory currentBalances) external override {
        // solhint-disable-previous-line no-empty-blocks
    }

    function onBeforeRemove(uint256[] memory currentBalances) external override {
        // solhint-disable-previous-line no-empty-blocks
    }

    function onAddLiquidityUnbalanced(
        address,
        uint256[] memory exactAmountsIn,
        uint256[] memory
    ) external pure override returns (uint256 bptAmountOut) {
        bptAmountOut = exactAmountsIn[0];
    }

    function onAddLiquiditySingleTokenInForExactBptOut(
        address,
        IERC20,
        uint256 exactBptAmountOut,
        uint256[] memory
    ) external pure override returns (uint256 amountIn) {
        return exactBptAmountOut;
    }

    function onAddLiquidityCustom(
        address,
        bytes memory userData,
        uint256[] memory currentBalances
    ) external pure override returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) {
        amountsIn = currentBalances;
        bptAmountOut = currentBalances[0];
        returnData = userData;
    }
}
