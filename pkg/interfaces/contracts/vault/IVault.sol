// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVaultAdmin } from "./IVaultAdmin.sol";
import { IVaultExtension } from "./IVaultExtension.sol";
import { IVaultMain } from "./IVaultMain.sol";
import { IVaultErrors } from "./IVaultErrors.sol";
import { IVaultEvents } from "./IVaultEvents.sol";

interface IVault is IVaultMain, IVaultExtension, IVaultAdmin, IVaultErrors, IVaultEvents {
    // solhint-disable-previous-line no-empty-blocks
}
