// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import "../ERC20BalancerPoolToken.sol";

contract ERC20PoolMock is ERC20BalancerPoolToken, IBasePool {
    using FixedPoint for uint256;

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
    ) external returns (uint256[] memory amountsIn) {
        emit OnAddLiquidityCalled(sender, currentBalances, maxAmountsIn, userData);

        return maxAmountsIn;
    }

    function onRemoveLiquidity(
        address sender,
        uint256[] memory currentBalances,
        uint256[] memory minAmountsOut,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut) {
        emit OnRemoveLiquidityCalled(sender, currentBalances, userData);

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
}
