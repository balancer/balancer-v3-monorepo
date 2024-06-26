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
import { RouterMock } from "@balancer-labs/v3-vault/contracts/test/RouterMock.sol";

import { VeBALFeeDiscountHookExample } from "../../contracts/VeBALFeeDiscountHookExample.sol";

contract VeBALFeeDiscountHookExampleTest is BaseVaultTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public override {
        super.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        // Grants to LP the ability to change static swap fee percentage
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), lp);
    }

    function createHook() internal override returns (address) {
        // lp will be the owner of the hook. Only LP is able to set hook fee percentages.
        vm.prank(lp);
        address veBalFeeHook = address(
            new VeBALFeeDiscountHookExample(
                IVault(address(vault)),
                address(factoryMock),
                address(veBAL),
                address(router)
            )
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

    function testCreationWithWrongFactory() public {
        address veBalFeePool = _createPoolToRegister();
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.HookRegistrationFailed.selector,
                poolHooksContract,
                veBalFeePool,
                address(factoryMock)
            )
        );
        _registerPoolWithHook(veBalFeePool, tokenConfig, address(factoryMock));
    }

    function testSuccessfulRegistry() public {
        // Registering with allowed factory
        address veBalFeePool = factoryMock.createPool("Test Pool", "TEST");
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        _registerPoolWithHook(veBalFeePool, tokenConfig, address(factoryMock));

        HooksConfig memory hooksConfig = vault.getHooksConfig(veBalFeePool);

        assertEq(hooksConfig.hooksContract, poolHooksContract, "Wrong poolHooksContract");
        assertEq(hooksConfig.shouldCallComputeDynamicSwapFee, true, "shouldCallComputeDynamicSwapFee is false");
    }

    function testUntrustedRouter() public {
        // Create an untrusted router
        RouterMock untrustedRouter = new RouterMock(IVault(address(vault)), weth, permit2);
        vm.label(address(untrustedRouter), "untrusted router");

        uint256 swapAmount = poolInitAmount / 100;

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                VeBALFeeDiscountHookExample.RouterNotTrustedByHook.selector,
                poolHooksContract,
                address(untrustedRouter)
            )
        );
        untrustedRouter.swapSingleTokenExactIn(pool, dai, usdc, swapAmount, swapAmount, MAX_UINT256, false, bytes(""));
    }

    function testSwapWithoutVeBal() public {
        assertEq(veBAL.balanceOf(bob), 0, "Bob still has veBAL");

        _doSwapAndCheckBalances();
    }

    function testSwapWithVeBal() public {
        // Mint 1 veBAL to bob, so he's able to receive the fee discount
        veBAL.mint(address(bob), 1);
        assertGt(veBAL.balanceOf(bob), 0, "Bob does not have veBAL");

        _doSwapAndCheckBalances();
    }

    function _doSwapAndCheckBalances() private {
        // 10% swap fee. Since vault does not have swap fee, the fee will stay in the pool
        uint256 swapFeePercentage = 1e17;

        vm.prank(lp);
        vault.setStaticSwapFeePercentage(pool, swapFeePercentage);

        uint256 exactAmountIn = poolInitAmount / 100;
        // PoolMock uses a linear math with rate 1, so amountIn = amountOut if no fees are applied
        uint256 expectedAmountOut = exactAmountIn;
        // If bob has veBAL, he gets a 50% discount
        bool bobHasVeBAL = veBAL.balanceOf(bob) > 0;
        uint256 expectedHookFee = exactAmountIn.mulDown(swapFeePercentage) / (bobHasVeBAL ? 2 : 1);
        // Hook fee will remain in the pool, so the expected amount out discounts the fees
        expectedAmountOut -= expectedHookFee;

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(bob));

        vm.prank(bob);
        router.swapSingleTokenExactIn(pool, dai, usdc, exactAmountIn, expectedAmountOut, MAX_UINT256, false, bytes(""));

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(bob));

        // Bob's balance of DAI is supposed to decrease, since DAI is the token in
        assertEq(
            balancesBefore.userTokens[daiIdx] - balancesAfter.userTokens[daiIdx],
            exactAmountIn,
            "Bob's DAI balance is wrong"
        );
        // Bob's balance of USDC is supposed to increase, since USDC is the token out
        assertEq(
            balancesAfter.userTokens[usdcIdx] - balancesBefore.userTokens[usdcIdx],
            expectedAmountOut,
            "Bob's USDC balance is wrong"
        );

        // Vault's balance of DAI is supposed to increase, since DAI was added by Bob
        assertEq(
            balancesAfter.vaultTokens[daiIdx] - balancesBefore.vaultTokens[daiIdx],
            exactAmountIn,
            "Vault's DAI balance is wrong"
        );
        // Vault's balance of USDC is supposed to decrease, since USDC was given to Bob
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            expectedAmountOut,
            "Vault's USDC balance is wrong"
        );

        // Pool deltas should equal vault's deltas
        assertEq(
            balancesAfter.poolTokens[daiIdx] - balancesBefore.poolTokens[daiIdx],
            exactAmountIn,
            "Pool's DAI balance is wrong"
        );
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            expectedAmountOut,
            "Pool's USDC balance is wrong"
        );
    }

    // Registry tests require a new pool, because an existing pool may be already registered
    function _createPoolToRegister() private returns (address newPool) {
        newPool = address(new PoolMock(IVault(address(vault)), "VeBAL Fee Pool", "veBALFeePool"));
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
