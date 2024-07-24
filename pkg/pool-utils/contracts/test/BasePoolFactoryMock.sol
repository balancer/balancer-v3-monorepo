// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    TokenConfig,
    PoolRoleAccounts,
    LiquidityManagement
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolFactory } from "../BasePoolFactory.sol";

contract BasePoolFactoryMock is BasePoolFactory {
    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        bytes memory creationCode
    ) BasePoolFactory(vault, pauseWindowDuration, creationCode) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function manualEnsureEnabled() external view {
        _ensureEnabled();
    }

    function manualRegisterPoolWithFactory(address pool) external {
        _registerPoolWithFactory(pool);
    }

    function manualRegisterPoolWithVault(
        address pool,
        TokenConfig[] memory tokens,
        uint256 swapFeePercentage,
        bool protocolFeeExempt,
        PoolRoleAccounts memory roleAccounts,
        address poolHooksContract,
        LiquidityManagement memory liquidityManagement
    ) external {
        _registerPoolWithVault(
            pool,
            tokens,
            swapFeePercentage,
            protocolFeeExempt,
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );
    }

    function manualCreate(string memory name, string memory symbol, bytes32 salt) external returns (address) {
        return _create(abi.encode(getVault(), name, symbol), salt);
    }
}
