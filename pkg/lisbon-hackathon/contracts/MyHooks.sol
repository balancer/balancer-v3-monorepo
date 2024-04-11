// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { PoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { BaseHooks } from "@balancer-labs/v3-pool-with-hooks/contracts/BaseHooks.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { SwapLocals } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import { PoolData } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

/// @notice A scaffold hooks implementation
contract MyHooks is BaseHooks {
    constructor() {
        // solhint-disable-previous-line no-empty-blocks
    }

    function availableHooks() external pure override returns (PoolHooks memory) {
        return
            PoolHooks({ // Set true for any hook you want to support
                shouldCallBeforeInitialize: false,
                shouldCallAfterInitialize: false,
                shouldCallBeforeAddLiquidity: false,
                shouldCallAfterAddLiquidity: false,
                shouldCallBeforeRemoveLiquidity: false,
                shouldCallAfterRemoveLiquidity: false,
                shouldCallBeforeSwap: true,
                shouldCallAfterSwap: false
            });
    }

    function supportsDynamicFee() external pure override returns (bool) {
        return true;
    }

    /// @dev Checks if the trader has passed the required cooldown period between trades.
    function _onBeforeSwap(IBasePool.PoolSwapParams memory /* params */) internal virtual override returns (bool) {
        return true;
    }

    function _computeFee(
        PoolData memory /* poolData */,
        SwapLocals memory /* vars */
    ) internal virtual override returns (uint256) {
        return 0;
    }
}
