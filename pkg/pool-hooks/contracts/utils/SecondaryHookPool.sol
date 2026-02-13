// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { HookFlags } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";

abstract contract SecondaryHookPool {
    // solhint-disable private-vars-leading-underscore
    uint256 internal constant BEFORE_INITIALIZE = 1;
    uint256 internal constant AFTER_INITIALIZE = 1 << 1;
    uint256 internal constant BEFORE_SWAP = 1 << 2;
    uint256 internal constant AFTER_SWAP = 1 << 3;
    uint256 internal constant BEFORE_ADD_LIQUIDITY = 1 << 4;
    uint256 internal constant AFTER_ADD_LIQUIDITY = 1 << 5;
    uint256 internal constant BEFORE_REMOVE_LIQUIDITY = 1 << 6;
    uint256 internal constant AFTER_REMOVE_LIQUIDITY = 1 << 7;
    uint256 internal constant COMPUTE_DYNAMIC_SWAP_FEE = 1 << 8;

    // Support pool types that register themselves as their own hook in the Vault, but also support forwarding to a
    // secondary hook.
    address internal immutable _secondaryHookContract;

    // Store which flags the external hook implements. Storing these as immutables saves gas vs. a memory read of the
    // hook flags each time a hook is called. It is a bit mask to reduce bytecode.
    uint256 internal immutable _secondaryHookMask;

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

    constructor(address hookContract) {
        _secondaryHookContract = hookContract;

        if (hookContract != address(0)) {
            // Note that we don't look at `enableHookAdjustedAmounts` here. It's important to return the full structure
            // in the pool's `getHookFlags` so that it will be stored in the Vault, but here we only care about the
            // flags related to calling hook functions.
            HookFlags memory flags = IHooks(hookContract).getHookFlags();
            uint256 mask;

            // prettier-ignore
            {
                if (flags.shouldCallBeforeInitialize) mask |= BEFORE_INITIALIZE;
                if (flags.shouldCallAfterInitialize) mask |= AFTER_INITIALIZE;
                if (flags.shouldCallBeforeSwap) mask |= BEFORE_SWAP;
                if (flags.shouldCallAfterSwap) mask |= AFTER_SWAP;
                if (flags.shouldCallBeforeAddLiquidity) mask |= BEFORE_ADD_LIQUIDITY;
                if (flags.shouldCallAfterAddLiquidity) mask |= AFTER_ADD_LIQUIDITY;
                if (flags.shouldCallBeforeRemoveLiquidity) mask |= BEFORE_REMOVE_LIQUIDITY;
                if (flags.shouldCallAfterRemoveLiquidity) mask |= AFTER_REMOVE_LIQUIDITY;

                // Should generally not be set for a pool type that already defines a dynamic swap fee.
                // If such a pool allows secondary hooks, it should either disallow secondary hooks that also define it,
                // or accommodate it somehow.
                if (flags.shouldCallComputeDynamicSwapFee) mask |= COMPUTE_DYNAMIC_SWAP_FEE;
            }

            _secondaryHookMask = mask;
        }
    }

    // Check the bit mask for a particular flag.
    function _secondaryHookShouldCall(uint256 bit) internal view returns (bool) {
        return (_secondaryHookMask & bit) != 0;
    }

    function _ensureHookContract() internal view {
        if (_secondaryHookContract == address(0)) {
            // Should never happen if the hook is configured properly (i.e., getHookFlags returns correct values
            // according to the implementation) and the `onlyWithHookContract` modifier is correctly applied.
            // It should be placed on hook functions that are *only* implemented in the secondary hook.
            revert HookFunctionNotImplemented();
        }
    }
}
