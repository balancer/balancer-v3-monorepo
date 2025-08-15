// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IStableSurgeHook {
    /**
     * @notice A new `StableSurgeHook` contract has been registered successfully.
     * @dev If the registration fails the call will revert, so there will be no event.
     * @param pool The pool on which the hook was registered
     * @param factory The factory that registered the pool
     */
    event StableSurgeHookRegistered(address indexed pool, address indexed factory);
}
