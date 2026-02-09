// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { HookFlags } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";

abstract contract SecondaryHookPool {
    // Support pool types that register themselves as their own hook in the Vault, but also support forwarding to a
    // secondary hook.
    address internal immutable _secondaryHookContract;
 
    /**
     * @notice A hook function was called that was not implemented by a secondary hook.
     * @dev This could really only happen if `getHookFlags` was misconfigured.
     */
    error HookFunctionNotImplemented();

    /// @dev Can only call hook functions not defined by the main pool if the secondary hook implements them.
    modifier onlyWithHookContract() {
        _ensureHookContract();
        _;
    }

    // Store which flags the external hook implements. Storing these as immutables saves gas vs. a memory read of the
    // hook flags each time a hook is called.
    bool internal immutable _secondaryHookHasBeforeInitialize;
    bool internal immutable _secondaryHookHasAfterInitialize;
    bool internal immutable _secondaryHookHasBeforeSwap;
    bool internal immutable _secondaryHookHasAfterSwap;
    bool internal immutable _secondaryHookHasBeforeAddLiquidity;
    bool internal immutable _secondaryHookHasAfterAddLiquidity;
    bool internal immutable _secondaryHookHasBeforeRemoveLiquidity;
    bool internal immutable _secondaryHookHasAfterRemoveLiquidity;
    bool internal immutable _secondaryHookHasDynamicSwapFee;

    constructor(address hookContract) {
        _secondaryHookContract = hookContract;

        if (hookContract != address(0)) {
            HookFlags memory flags = IHooks(hookContract).getHookFlags();

            _secondaryHookHasBeforeInitialize = flags.shouldCallBeforeInitialize;
            _secondaryHookHasAfterInitialize = flags.shouldCallAfterInitialize;
            _secondaryHookHasBeforeSwap = flags.shouldCallBeforeSwap;
            _secondaryHookHasAfterSwap = flags.shouldCallAfterSwap;
            _secondaryHookHasBeforeAddLiquidity = flags.shouldCallBeforeAddLiquidity;
            _secondaryHookHasAfterAddLiquidity = flags.shouldCallAfterAddLiquidity;
            _secondaryHookHasBeforeRemoveLiquidity = flags.shouldCallBeforeRemoveLiquidity;
            _secondaryHookHasAfterRemoveLiquidity = flags.shouldCallAfterRemoveLiquidity;
            // Should generally not be set for a pool type that already defines a dynamic swap fee.
            // If such a pool allows secondary hooks, it should either disallow secondary hooks that also define it,
            // or accommodate it somehow.
            _secondaryHookHasDynamicSwapFee = flags.shouldCallComputeDynamicSwapFee;
        }
    }

    function _ensureHookContract() internal view {
        if (_secondaryHookContract == address(0)) {
            // Should not happen. Hook flags would not go beyond ReClamm-required ones without a contract.
            revert HookFunctionNotImplemented();
        }
    }
}
