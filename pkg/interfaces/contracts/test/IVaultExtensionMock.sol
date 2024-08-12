// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { TokenConfig, PoolRoleAccounts, LiquidityManagement } from "../../contracts/vault/VaultTypes.sol";

interface IVaultExtensionMock {
    // Used in tests to circumvent minimum swap fees.
    function manuallySetSwapFee(address pool, uint256 swapFeePercentage) external;

    function manualRegisterPoolReentrancy(
        address pool,
        TokenConfig[] memory tokenConfig,
        uint256 swapFeePercentage,
        uint32 pauseWindowEndTime,
        bool protocolFeeExempt,
        PoolRoleAccounts calldata roleAccounts,
        address poolHooksContract,
        LiquidityManagement calldata liquidityManagement
    ) external;
}
