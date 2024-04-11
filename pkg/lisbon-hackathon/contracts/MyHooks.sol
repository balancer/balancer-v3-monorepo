// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { PoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { BaseHooks } from "@balancer-labs/v3-pool-with-hooks/contracts/BaseHooks.sol";


/// @notice A scaffold hooks implementation
contract MyHooks is BaseHooks {

    constructor() {}

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

    /// @dev Checks if the trader has passed the required cooldown period between trades.
    function _onBeforeSwap(IBasePool.PoolSwapParams memory params) internal virtual override returns (bool) {
        return true;
    }
}
