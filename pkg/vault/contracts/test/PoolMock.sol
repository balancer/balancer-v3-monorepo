// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { PoolMockCommon } from "./PoolMockCommon.sol";

contract PoolMock is PoolMockCommon, IPoolLiquidity {
    constructor(IVault vault, string memory name, string memory symbol) PoolMockCommon(vault, name, symbol) {
        // solhint-previous-line no-empty-blocks
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
}
