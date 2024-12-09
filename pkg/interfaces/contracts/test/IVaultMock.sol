// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { IVaultExtensionMock } from "./IVaultExtensionMock.sol";
import { IVaultStorageMock } from "./IVaultStorageMock.sol";
import { IVaultAdminMock } from "./IVaultAdminMock.sol";
import { IVaultMainMock } from "./IVaultMainMock.sol";
import { IVault } from "../vault/IVault.sol";

/// @dev One-fits-all solution for hardhat tests. Use the typechain type for errors, events and functions.
interface IVaultMock is IVault, IVaultMainMock, IVaultExtensionMock, IVaultAdminMock, IVaultStorageMock, IERC20Errors {
    // solhint-disable-previous-line no-empty-blocks
}
