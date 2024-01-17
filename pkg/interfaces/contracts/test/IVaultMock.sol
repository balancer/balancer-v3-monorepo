// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { IAuthentication } from "../solidity-utils/helpers/IAuthentication.sol";
import { IVault } from "../vault/IVault.sol";
import { IVaultEvents } from "../vault/IVaultEvents.sol";
import { IVaultMainMock } from "./IVaultMainMock.sol";
import { IVaultExtensionMock } from "./IVaultExtensionMock.sol";

/// @dev One-fits-all solution for hardhat tests. Use the typechain type for errors, events and functions.
interface IVaultMock is IVault, IVaultMainMock, IVaultExtensionMock, IERC20Errors, IAuthentication {}
