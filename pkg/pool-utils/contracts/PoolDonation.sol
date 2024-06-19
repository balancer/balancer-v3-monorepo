// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

contract PoolDonation is IPoolLiquidity {
    /// @inheritdoc IPoolLiquidity
    function onAddLiquidityCustom(
        address,
        uint256[] memory maxAmountsInScaled18,
        uint256 minBptAmountOut,
        uint256[] memory,
        bytes memory
    ) external pure virtual returns (uint256[] memory, uint256, uint256[] memory, bytes memory) {
        if (minBptAmountOut > 0) {
            revert IVaultErrors.BptAmountOutBelowMin(0, minBptAmountOut);
        }

        // This is a donation mechanism. maxAmountsInScaled18 is the amount of tokens to be inserted in the pool,
        // with no BPTs out and no fees.
        return (maxAmountsInScaled18, minBptAmountOut, new uint256[](maxAmountsInScaled18.length), userData);
    }

    /// @inheritdoc IPoolLiquidity
    function onRemoveLiquidityCustom(
        address,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external pure virtual returns (uint256, uint256[] memory, uint256[] memory, bytes memory) {
        revert IVaultErrors.OperationNotSupported();
    }
}
