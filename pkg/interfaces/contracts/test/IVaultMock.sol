// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "../solidity-utils/helpers/IAuthentication.sol";
import { IVault } from "../vault/IVault.sol";
import { IVaultEvents } from "../vault/IVaultEvents.sol";
import { IVaultMainMock } from "./IVaultMainMock.sol";
import { IVaultExtensionMock } from "./IVaultExtensionMock.sol";
import { TokenConfig } from "../vault/VaultTypes.sol";
import { IRateProvider } from "../vault/IRateProvider.sol";

/// @dev One-fits-all solution for hardhat tests. Use the typechain type for errors, events and functions.
interface IVaultMock is IVault, IVaultMainMock, IVaultExtensionMock, IERC20Errors, IAuthentication {
    /// @dev Convenience function for constructing TokenConfig[] from IERC20[].
    function buildTokenConfig(IERC20[] memory tokens) external pure returns (TokenConfig[] memory tokenConfig);

    /// @dev Convenience function for constructing TokenConfig[] from IERC20[] and IRateProvider[].
    function buildTokenConfig(
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders
    ) external pure returns (TokenConfig[] memory tokenConfig);

    /// @dev Convenience function for constructing TokenConfig[] from IERC20[] and IRateProvider[].
    function buildTokenConfig(
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders,
        bool[] memory yieldExemptFlags
    ) external pure returns (TokenConfig[] memory tokenConfig);
}
