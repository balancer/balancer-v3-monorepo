// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVaultExtension } from "./IVaultExtension.sol";
import { IVaultMain } from "./IVaultMain.sol";

interface IVault is IVaultMain, IVaultExtension {

}
