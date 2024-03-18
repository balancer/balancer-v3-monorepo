// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVaultAdmin } from "./IVaultAdmin.sol";
import { IVaultExtension } from "./IVaultExtension.sol";
import { IVaultMain } from "./IVaultMain.sol";
import { IVaultErrors } from "./IVaultErrors.sol";
import { IVaultEvents } from "./IVaultEvents.sol";

interface IVault is IVaultMain, IVaultExtension, IVaultAdmin, IVaultErrors, IVaultEvents {
    /// @dev Returns the main Vault address.
    function vault() external view override(IVaultAdmin, IVaultExtension) returns (IVault);
}
