// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IProtocolFeeCollector } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeCollector.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract ProtocolFeeExemptionTest is BaseVaultTest {
    uint256 internal GLOBAL_SWAP_FEE = 50e16;
    uint256 internal GLOBAL_YIELD_FEE = 20e16;

    IProtocolFeeCollector internal feeCollector;
    PoolRoleAccounts internal roleAccounts;

    uint256 daiIdx;
    uint256 usdcIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        feeCollector = vault.getProtocolFeeCollector();
        IAuthentication feeCollectorAuth = IAuthentication(address(feeCollector));

        // Set default protocol fees
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setGlobalProtocolSwapFeePercentage.selector),
            alice
        );
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setGlobalProtocolYieldFeePercentage.selector),
            alice
        );

        vm.startPrank(alice);
        feeCollector.setGlobalProtocolSwapFeePercentage(GLOBAL_SWAP_FEE);
        feeCollector.setGlobalProtocolYieldFeePercentage(GLOBAL_YIELD_FEE);
        vm.stopPrank();
    }

    function testPrerequisites() public {
        assertEq(feeCollector.getGlobalProtocolSwapFeePercentage(), GLOBAL_SWAP_FEE);
        assertEq(feeCollector.getGlobalProtocolYieldFeePercentage(), GLOBAL_YIELD_FEE);
    }

    function testProtocolFeesWithoutExemption() public {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[daiIdx].token = IERC20(dai);
        tokenConfig[usdcIdx].token = IERC20(usdc);

        pool = address(new PoolMock(IVault(address(vault)), "Non-Exempt Pool", "NOTEXEMPT"));
        factoryMock.registerGeneralTestPool(address(pool), tokenConfig, 0, 365 days, false, roleAccounts);

        PoolConfig memory poolConfig = vault.getPoolConfig(pool);

        assertEq(poolConfig.aggregateProtocolSwapFeePercentage, GLOBAL_SWAP_FEE);
        assertEq(poolConfig.aggregateProtocolYieldFeePercentage, GLOBAL_YIELD_FEE);
    }

    function testWithProtocolFeeExemption() public {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[daiIdx].token = IERC20(dai);
        tokenConfig[usdcIdx].token = IERC20(usdc);

        pool = address(new PoolMock(IVault(address(vault)), "Exempt Pool", "EXEMPT"));
        factoryMock.registerGeneralTestPool(address(pool), tokenConfig, 0, 365 days, true, roleAccounts);

        PoolConfig memory poolConfig = vault.getPoolConfig(pool);

        assertEq(poolConfig.aggregateProtocolSwapFeePercentage, 0);
        assertEq(poolConfig.aggregateProtocolYieldFeePercentage, 0);
    }
}
