// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig, PoolConfig, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract ProtocolFeeExemptionTest is BaseVaultTest {
    uint256 internal GLOBAL_SWAP_FEE = 50e16;
    uint256 internal GLOBAL_YIELD_FEE = 20e16;

    PoolRoleAccounts internal roleAccounts;

    uint256 daiIdx;
    uint256 usdcIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        IAuthentication feeControllerAuth = IAuthentication(address(feeController));

        // Set default protocol fees.
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolSwapFeePercentage.selector),
            alice
        );
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolYieldFeePercentage.selector),
            alice
        );

        vm.startPrank(alice);
        feeController.setGlobalProtocolSwapFeePercentage(GLOBAL_SWAP_FEE);
        feeController.setGlobalProtocolYieldFeePercentage(GLOBAL_YIELD_FEE);
        vm.stopPrank();
    }

    function testPrerequisites() public view {
        assertEq(feeController.getGlobalProtocolSwapFeePercentage(), GLOBAL_SWAP_FEE);
        assertEq(feeController.getGlobalProtocolYieldFeePercentage(), GLOBAL_YIELD_FEE);
    }

    function testProtocolFeesWithoutExemption() public {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[daiIdx].token = IERC20(dai);
        tokenConfig[usdcIdx].token = IERC20(usdc);

        pool = address(new PoolMock(IVault(address(vault)), "Non-Exempt Pool", "NOT-EXEMPT"));
        factoryMock.registerGeneralTestPool(pool, tokenConfig, 0, 365 days, false, roleAccounts, address(0));

        PoolConfig memory poolConfigBits = vault.getPoolConfig(pool);

        assertEq(poolConfigBits.aggregateSwapFeePercentage, GLOBAL_SWAP_FEE);
        assertEq(poolConfigBits.aggregateYieldFeePercentage, GLOBAL_YIELD_FEE);
    }

    function testWithProtocolFeeExemption() public {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[daiIdx].token = IERC20(dai);
        tokenConfig[usdcIdx].token = IERC20(usdc);

        pool = address(new PoolMock(IVault(address(vault)), "Exempt Pool", "EXEMPT"));
        factoryMock.registerGeneralTestPool(pool, tokenConfig, 0, 365 days, true, roleAccounts, address(0));

        PoolConfig memory poolConfigBits = vault.getPoolConfig(pool);

        assertEq(poolConfigBits.aggregateSwapFeePercentage, 0);
        assertEq(poolConfigBits.aggregateYieldFeePercentage, 0);
    }
}
