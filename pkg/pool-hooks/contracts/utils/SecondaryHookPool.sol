// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { HookFlags } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";

abstract contract SecondaryHookPool {
    // Support pool types that register themselves as their own hook in the Vault, but also support forwarding to a
    // secondary hook.
    address internal immutable _SECONDARY_HOOK_CONTRACT;

    error HookFunctionNotImplemented();

    /// @dev Can only call hook functions not defined by the main pool if the secondary hook implements them.
    modifier onlyWithHookContract() {
        _ensureHookContract();
        _;
    }

    // Store which flags the external hook implements. Storing these as immutables saves gas vs. a memory read of the
    // hook flags each time a hook is called.
    bool internal immutable _SECONDARY_HOOK_HAS_BEFORE_INITIALIZE;
    bool internal immutable _SECONDARY_HOOK_HAS_AFTER_INITIALIZE;
    bool internal immutable _SECONDARY_HOOK_HAS_BEFORE_SWAP;
    bool internal immutable _SECONDARY_HOOK_HAS_AFTER_SWAP;
    bool internal immutable _SECONDARY_HOOK_HAS_BEFORE_ADD_LIQUIDITY;
    bool internal immutable _SECONDARY_HOOK_HAS_AFTER_ADD_LIQUIDITY;
    bool internal immutable _SECONDARY_HOOK_HAS_BEFORE_REMOVE_LIQUIDITY;
    bool internal immutable _SECONDARY_HOOK_HAS_AFTER_REMOVE_LIQUIDITY;
    bool internal immutable _SECONDARY_HOOK_HAS_DYNAMIC_SWAP_FEE;

    constructor(address hookContract) {
        _SECONDARY_HOOK_CONTRACT = hookContract;

        if (hookContract != address(0)) {
            HookFlags memory flags = IHooks(hookContract).getHookFlags();

            _SECONDARY_HOOK_HAS_BEFORE_INITIALIZE = flags.shouldCallBeforeInitialize;
            _SECONDARY_HOOK_HAS_AFTER_INITIALIZE = flags.shouldCallAfterInitialize;
            _SECONDARY_HOOK_HAS_BEFORE_SWAP = flags.shouldCallBeforeSwap;
            _SECONDARY_HOOK_HAS_AFTER_SWAP = flags.shouldCallAfterSwap;
            _SECONDARY_HOOK_HAS_BEFORE_ADD_LIQUIDITY = flags.shouldCallBeforeAddLiquidity;
            _SECONDARY_HOOK_HAS_AFTER_ADD_LIQUIDITY = flags.shouldCallAfterAddLiquidity;
            _SECONDARY_HOOK_HAS_BEFORE_REMOVE_LIQUIDITY = flags.shouldCallBeforeRemoveLiquidity;
            _SECONDARY_HOOK_HAS_AFTER_REMOVE_LIQUIDITY = flags.shouldCallAfterRemoveLiquidity;
            _SECONDARY_HOOK_HAS_DYNAMIC_SWAP_FEE = flags.shouldCallComputeDynamicSwapFee;
        }
    }

    function _ensureHookContract() internal view {
        if (_SECONDARY_HOOK_CONTRACT == address(0)) {
            // Should not happen. Hook flags would not go beyond ReClamm-required ones without a contract.
            revert HookFunctionNotImplemented();
        }
    }
}
