// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IAuthentication } from "../solidity-utils/helpers/IAuthentication.sol";
import { IVaultExtension } from "./IVaultExtension.sol";
import { IVaultErrors } from "./IVaultErrors.sol";
import { IVaultEvents } from "./IVaultEvents.sol";
import { IVaultAdmin } from "./IVaultAdmin.sol";
import { IVaultMain } from "./IVaultMain.sol";

/// @notice Composite interface for all Vault operations: swap, add/remove liquidity, and associated queries.
interface IVault is IVaultMain, IVaultExtension, IVaultAdmin, IVaultErrors, IVaultEvents, IAuthentication {
    /// @return vault The main Vault address.
    function vault() external view override(IVaultAdmin, IVaultExtension) returns (IVault);
}
