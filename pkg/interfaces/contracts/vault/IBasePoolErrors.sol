// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IBasePoolErrors {
    /// @dev Indicates the caller is not allowed to execute this function; it should be executed by the Vault only.
    error CallerNotVault();

    /// @dev Indicates that the pool does not support the given join kind.
    error UnhandledJoinKind();

    /// @dev Indicates that the pool does not support the given exit kind.
    error UnhandledExitKind();

    /// @dev Indicates that the pool does not implement a callback that it was configured for.
    error CallbackNotImplemented();

    // TODO: move this to Vault.
    /// @dev Indicates the number of pool tokens is below the minimum allowed.
    error MinTokens();

    /// @dev Indicates the number of pool tokens is above the maximum allowed.
    error MaxTokens();
}
