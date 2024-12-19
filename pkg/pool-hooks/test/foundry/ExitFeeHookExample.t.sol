// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    HooksConfig,
    LiquidityManagement,
    PoolConfig,
    PoolRoleAccounts,
    TokenConfig
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { ExitFeeHookExample } from "../../contracts/ExitFeeHookExample.sol";

contract ExitFeeHookExampleTest is BaseVaultTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    // 10% exit fee
    uint64 internal constant EXIT_FEE_PERCENTAGE = 10e16;

    function setUp() public override {
        super.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function createHook() internal override returns (address) {
        // lp will be the owner of the hook. Only LP is able to set hook fee percentages.
        vm.prank(lp);
        address exitFeeHook = address(new ExitFeeHookExample(IVault(address(vault))));
        vm.label(exitFeeHook, "Exit Fee Hook");
        return exitFeeHook;
    }

    // Overrides pool creation to set liquidityManagement (disables unbalanced liquidity and enables donation)
    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal virtual override returns (address newPool, bytes memory poolArgs) {
        string memory name = "ERC20 Pool";
        string memory symbol = "ERC20POOL";

        newPool = address(deployPoolMock(IVault(address(vault)), name, symbol));
        vm.label(newPool, label);

        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = lp;

        LiquidityManagement memory liquidityManagement;
        liquidityManagement.disableUnbalancedLiquidity = true;
        liquidityManagement.enableDonation = true;

        vm.expectEmit();
        emit ExitFeeHookExample.ExitFeeHookExampleRegistered(poolHooksContract(), newPool);

        factoryMock.registerPool(
            newPool,
            vault.buildTokenConfig(tokens.asIERC20()),
            roleAccounts,
            poolHooksContract(),
            liquidityManagement
        );

        // poolArgs is used to check pool deployment address with create2.
        poolArgs = abi.encode(vault, name, symbol);
    }

    function testRegistryWithWrongDonationFlag() public {
        address exitFeePool = _createPoolToRegister();
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );
        vm.expectRevert(ExitFeeHookExample.PoolDoesNotSupportDonation.selector);
        _registerPoolWithHook(exitFeePool, tokenConfig, false);
    }

    function testSuccessfulRegistry() public {
        address exitFeePool = _createPoolToRegister();
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        _registerPoolWithHook(exitFeePool, tokenConfig, true);

        PoolConfig memory poolConfig = vault.getPoolConfig(exitFeePool);
        HooksConfig memory hooksConfig = vault.getHooksConfig(exitFeePool);

        assertTrue(poolConfig.liquidityManagement.enableDonation, "enableDonation is false");
        assertTrue(poolConfig.liquidityManagement.disableUnbalancedLiquidity, "disableUnbalancedLiquidity is false");
        assertTrue(hooksConfig.enableHookAdjustedAmounts, "enableHookAdjustedAmounts is false");
        assertEq(hooksConfig.hooksContract, poolHooksContract(), "hooksContract is wrong");
    }

    // Exit fee returns to LPs
    function testExitFeeReturnToLPs() public virtual {
        vm.expectEmit();
        emit ExitFeeHookExample.ExitFeePercentageChanged(poolHooksContract(), EXIT_FEE_PERCENTAGE);

        vm.prank(lp);
        ExitFeeHookExample(poolHooksContract()).setExitFeePercentage(EXIT_FEE_PERCENTAGE);
        uint256 amountOut = poolInitAmount() / 2;
        uint256 hookFee = amountOut.mulDown(EXIT_FEE_PERCENTAGE);
        uint256[] memory minAmountsOut = [amountOut - hookFee, amountOut - hookFee].toMemoryArray();

        BaseVaultTest.Balances memory balancesBefore = getBalances(lp);

        vm.expectEmit();
        emit ExitFeeHookExample.ExitFeeCharged(pool(), IERC20(dai), hookFee);

        vm.expectEmit();
        emit ExitFeeHookExample.ExitFeeCharged(pool(), IERC20(usdc), hookFee);

        vm.prank(lp);
        router.removeLiquidityProportional(pool(), 2 * amountOut, minAmountsOut, false, bytes(""));

        BaseVaultTest.Balances memory balancesAfter = getBalances(lp);

        // LP gets original liquidity minus hook fee
        assertEq(
            balancesAfter.lpTokens[daiIdx] - balancesBefore.lpTokens[daiIdx],
            amountOut - hookFee,
            "LP's DAI amount is wrong"
        );
        assertEq(
            balancesAfter.lpTokens[usdcIdx] - balancesBefore.lpTokens[usdcIdx],
            amountOut - hookFee,
            "LP's USDC amount is wrong"
        );
        assertEq(balancesBefore.lpBpt - balancesAfter.lpBpt, 2 * amountOut, "LP's BPT amount is wrong");

        // Pool balances decrease by amountOut, and receive hook fee
        assertEq(
            balancesBefore.poolTokens[daiIdx] - balancesAfter.poolTokens[daiIdx],
            amountOut - hookFee,
            "Pool's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            amountOut - hookFee,
            "Pool's USDC amount is wrong"
        );
        assertEq(balancesBefore.poolSupply - balancesAfter.poolSupply, 2 * amountOut, "BPT supply amount is wrong");

        // Same happens with Vault balances: decrease by amountOut, keep hook fee
        assertEq(
            balancesBefore.vaultTokens[daiIdx] - balancesAfter.vaultTokens[daiIdx],
            amountOut - hookFee,
            "Vault's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            amountOut - hookFee,
            "Vault's USDC amount is wrong"
        );

        // Hook balances remain unchanged
        assertEq(balancesBefore.hookTokens[daiIdx], balancesAfter.hookTokens[daiIdx], "Hook's DAI amount is wrong");
        assertEq(balancesBefore.hookTokens[usdcIdx], balancesAfter.hookTokens[usdcIdx], "Hook's USDC amount is wrong");
        assertEq(balancesBefore.hookBpt, balancesAfter.hookBpt, "Hook's BPT amount is wrong");
    }

    function testPercentageTooHigh() public {
        uint64 highFee = uint64(FixedPoint.ONE);

        vm.expectRevert(
            abi.encodeWithSelector(ExitFeeHookExample.ExitFeeAboveLimit.selector, highFee, EXIT_FEE_PERCENTAGE)
        );
        vm.prank(lp);
        ExitFeeHookExample(poolHooksContract()).setExitFeePercentage(highFee);
    }

    // Registry tests require a new pool(), because an existent pool may be already registered
    function _createPoolToRegister() private returns (address newPool) {
        newPool = address(deployPoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL"));
        vm.label(newPool, "Exit Fee Pool");
    }

    function _registerPoolWithHook(address exitFeePool, TokenConfig[] memory tokenConfig, bool enableDonation) private {
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = lp;

        LiquidityManagement memory liquidityManagement;
        liquidityManagement.disableUnbalancedLiquidity = true;
        liquidityManagement.enableDonation = enableDonation;

        factoryMock.registerPool(exitFeePool, tokenConfig, roleAccounts, poolHooksContract(), liquidityManagement);
    }
}
