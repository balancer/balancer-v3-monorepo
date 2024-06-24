// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import {
    HooksConfig,
    LiquidityManagement,
    PoolRoleAccounts,
    TokenConfig
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";
import { PoolFactoryMock } from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";

import { VeBALFeeDiscountHookExample } from "../../contracts/VeBALFeeDiscountHookExample.sol";

contract VeBALFeeDiscountHookExampleTest is BaseVaultTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public override {
        super.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function createHook() internal override returns (address) {
        // lp will be the owner of the hook. Only LP is able to set hook fee percentages.
        vm.prank(lp);
        address veBalFeeHook = address(
            new VeBALFeeDiscountHookExample(IVault(address(vault)), address(factoryMock), address(veBAL))
        );
        vm.label(veBalFeeHook, "VeBAL Fee Hook");
        return veBalFeeHook;
    }

    function testRegistryWithWrongFactory() public {
        address veBalFeePool = _createPoolToRegister();
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        uint32 pauseWindowEndTime = IVaultAdmin(address(vault)).getPauseWindowEndTime();
        uint32 bufferPeriodDuration = IVaultAdmin(address(vault)).getBufferPeriodDuration();
        uint32 pauseWindowDuration = pauseWindowEndTime - bufferPeriodDuration;
        address unauthorizedFactory = address(new PoolFactoryMock(IVault(address(vault)), pauseWindowDuration));

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.HookRegistrationFailed.selector,
                poolHooksContract,
                veBalFeePool,
                unauthorizedFactory
            )
        );
        _registerPoolWithHook(veBalFeePool, tokenConfig, unauthorizedFactory);
    }

    function testSuccessfulRegistry() public {
        address veBalFeePool = _createPoolToRegister();
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        _registerPoolWithHook(veBalFeePool, tokenConfig, address(factoryMock));

        HooksConfig memory hooksConfig = vault.getHooksConfig(veBalFeePool);

        assertEq(hooksConfig.hooksContract, poolHooksContract, "pool's hooks contract is wrong");
        assertEq(hooksConfig.shouldCallComputeDynamicSwapFee, true, "pool's shouldCallComputeDynamicSwapFee is wrong");
    }

    // User without vebal
    // User with vebal

    // Registry tests require a new pool, because an existent pool may be already registered
    function _createPoolToRegister() private returns (address newPool) {
        newPool = address(new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL"));
        vm.label(newPool, "VeBAL Fee Pool");
    }

    function _registerPoolWithHook(address exitFeePool, TokenConfig[] memory tokenConfig, address factory) private {
        PoolRoleAccounts memory roleAccounts;
        LiquidityManagement memory liquidityManagement;

        PoolFactoryMock(factory).registerPool(
            exitFeePool,
            tokenConfig,
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );
    }
}
