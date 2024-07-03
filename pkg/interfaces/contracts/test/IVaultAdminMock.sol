// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IVaultAdminMock {
    function manualPauseVault() external;

    function manualUnpauseVault() external;

    function manualPausePool(address pool) external;

    function manualUnpausePool(address pool) external;

    function manualEnableRecoveryMode(address pool) external;

    function manualDisableRecoveryMode(address pool) external;

    function manualReentrancyAddLiquidityToBuffer(
        IERC4626 wrappedToken,
        uint256 amountUnderlying,
        uint256 amountWrapped,
        address sharesOwner
    ) external;

    function manualReentrancyRemoveLiquidityFromBuffer(
        IERC4626 wrappedToken,
        uint256 sharesToRemove,
        address sharesOwner
    ) external;

    function mockWithValidPercentage(uint256 percentage) external view;

    function mockEnsurePoolNotInRecoveryMode(address pool) external view;
}
