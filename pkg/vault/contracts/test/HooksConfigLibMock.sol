// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { HooksConfigLib } from "@balancer-labs/v3-vault/contracts/lib/HooksConfigLib.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

contract HooksConfigLibMock {
    using HooksConfigLib for PoolConfigBits;

    function callComputeDynamicSwapFeeHook(
        IBasePool.PoolSwapParams memory swapParams,
        address pool,
        uint256 staticSwapFeePercentage,
        IHooks hooksContract
    ) public view returns (bool, uint256) {
        return HooksConfigLib.callComputeDynamicSwapFeeHook(swapParams, pool, staticSwapFeePercentage, hooksContract);
    }

    function callBeforeSwapHook(IBasePool.PoolSwapParams memory swapParams, address pool, IHooks hooksContract) public {
        if (hooksContract.onBeforeSwap(swapParams, pool) == false) {
            // Hook contract implements onBeforeSwap, but it has failed, so reverts the transaction.
            revert IVaultErrors.BeforeSwapHookFailed();
        }
    }

    function callAfterSwapHook(
        PoolConfigBits config,
        uint256 amountCalculatedScaled18,
        uint256 amountCalculatedRaw,
        address router,
        SwapParams memory params,
        SwapState memory state,
        PoolData memory poolData,
        IHooks hooksContract
    ) public returns (uint256) {
        PoolConfigBits config_ = config;
        return
            config_.callAfterSwapHook(
                amountCalculatedScaled18,
                amountCalculatedRaw,
                router,
                params,
                state,
                poolData,
                hooksContract
            );
    }
}
