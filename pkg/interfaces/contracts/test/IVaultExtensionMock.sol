// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PoolRoleAccounts, LiquidityManagement } from "../../contracts/vault/VaultTypes.sol";
import { TokenConfig } from "../../contracts/solidity-utils/BasePoolTypes.sol";

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

    function manualInitializePoolReentrancy(
        address pool,
        address to,
        IERC20[] memory tokens,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external;
}
