// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { IVault } from "../vault/IVault.sol";
import { IVaultMainMock } from "./IVaultMainMock.sol";
import { IVaultExtensionMock } from "./IVaultExtensionMock.sol";
import { IVaultAdminMock } from "./IVaultAdminMock.sol";
import { IVaultStorageMock } from "./IVaultStorageMock.sol";

/// @dev One-fits-all solution for hardhat tests. Use the typechain type for errors, events and functions.
interface IVaultMock is IVault, IVaultMainMock, IVaultExtensionMock, IVaultAdminMock, IVaultStorageMock, IERC20Errors {
    // solhint-disable-previous-line no-empty-blocks
}
