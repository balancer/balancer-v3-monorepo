// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import "../ERC20BalancerPoolToken.sol";

contract ERC20PoolMock is ERC20BalancerPoolToken, IBasePool {
    IVault private immutable _vault;

    constructor(
        IVault vault,
        string memory name,
        string memory symbol,
        address factory,
        IERC20[] memory tokens,
        bool registerPool
    ) ERC20BalancerPoolToken(vault, name, symbol) {
        _vault = vault;

        if (registerPool) {
            vault.registerPool(factory, tokens);
        }
    }

    function onAddLiquidity(
        address sender,
        uint256[] memory currentBalances,
        uint256[] memory maxAmountsIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        emit OnAddLiquidityCalled(sender, currentBalances, maxAmountsIn, maxAmountsIn[0], userData);

        return (maxAmountsIn, maxAmountsIn[0]);
    }

    function onRemoveLiquidity(
        address sender,
        uint256[] memory currentBalances,
        uint256[] memory minAmountsOut,
        uint256 bptAmountIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut) {
        emit OnRemoveLiquidityCalled(sender, currentBalances, bptAmountIn, userData);

        return minAmountsOut;
    }
}
