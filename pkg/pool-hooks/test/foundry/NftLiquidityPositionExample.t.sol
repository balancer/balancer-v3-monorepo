// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { LiquidityManagement, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-vault/contracts/test/BasicAuthorizerMock.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { BatchRouterMock } from "@balancer-labs/v3-vault/contracts/test/BatchRouterMock.sol";
import { PoolFactoryMock } from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { RouterMock } from "@balancer-labs/v3-vault/contracts/test/RouterMock.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { NftLiquidityPositionExample } from "../../contracts/NftLiquidityPositionExample.sol";

contract NftLiquidityPositionExampleTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    // Maximum exit fee of 10%
    uint64 public constant MAX_EXIT_FEE_PERCENTAGE = 10e16;

    uint256 internal constant DEFAULT_AMP_FACTOR = 200;

    NftLiquidityPositionExample internal nftRouter;

    // Overrides `setUp` to include a deployment for NftLiquidityPositionExample.
    function setUp() public virtual override {
        BaseTest.setUp();

        approveNFTRouterForPool(IERC20(pool()));

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function onAfterDeployMainContracts() internal override {
        nftRouter = new NftLiquidityPositionExample(IVault(address(vault)), weth, permit2, "NFT LiquidityPosition v1");
        vm.label(address(nftRouter), "nftRouter");
    }

    function onAfterApproveUsersForMainContracts() internal override {
        for (uint256 i = 0; i < tokens.length; ++i) {
            permit2.approve(address(tokens[i]), address(nftRouter), type(uint160).max, type(uint48).max);
        }
    }

    function createHook() internal override returns (address) {
        return address(nftRouter);
    }

    function approveNFTRouterForPool(IERC20 bpt) internal {
        for (uint256 i = 0; i < users.length; ++i) {
            vm.startPrank(users[i]);
            bpt.approve(address(nftRouter), type(uint256).max);
            permit2.approve(address(bpt), address(nftRouter), type(uint160).max, type(uint48).max);
            vm.stopPrank();
        }
    }

    // Overrides pool creation to set liquidityManagement (disables unbalanced liquidity).
    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "NFT Pool";
        string memory symbol = "NFT Pool";

        newPool = address(deployPoolMock(IVault(address(vault)), name, symbol));
        vm.label(newPool, label);

        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = lp;

        LiquidityManagement memory liquidityManagement;
        liquidityManagement.disableUnbalancedLiquidity = true;
        liquidityManagement.enableDonation = true;

        factoryMock.registerPool(
            newPool,
            vault.buildTokenConfig(tokens.asIERC20()),
            roleAccounts,
            poolHooksContract(),
            liquidityManagement
        );

        poolArgs = abi.encode(vault, name, symbol);
    }

    function testAddLiquidity() public {
        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        uint256[] memory amountsIn = nftRouter.addLiquidityProportional(
            pool(),
            maxAmountsIn,
            DEFAULT_BPT_AMOUNT,
            false,
            bytes("")
        );
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(bob);

        // Bob sends correct lp tokens
        assertEq(
            balancesBefore.bobTokens[daiIdx] - balancesAfter.bobTokens[daiIdx],
            amountsIn[daiIdx],
            "bob's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.bobTokens[usdcIdx] - balancesAfter.bobTokens[usdcIdx],
            amountsIn[usdcIdx],
            "bob's USDC amount is wrong"
        );
        // Router should set correct lp data
        uint256 expectedTokenId = 0;
        assertEq(
            nftRouter.DEFAULT_BPT_AMOUNT(expectedTokenId),
            DEFAULT_BPT_AMOUNT,
            "DEFAULT_BPT_AMOUNT mapping is wrong"
        );
        assertEq(nftRouter.startTime(expectedTokenId), block.timestamp, "startTime mapping is wrong");
        assertEq(nftRouter.nftPool(expectedTokenId), pool(), "pool mapping is wrong");

        // Router should receive BPT instead of bob, he gets the NFT
        assertEq(
            BalancerPoolToken(pool()).balanceOf(address(nftRouter)),
            DEFAULT_BPT_AMOUNT,
            "NftRouter should hold BPT"
        );
        assertEq(nftRouter.ownerOf(expectedTokenId), bob, "bob should have an NFT");
        assertEq(balancesAfter.bobBpt, 0, "bob should not hold any BPT");
    }

    function testRemoveLiquidityWithHalfDecayFee() public {
        // Add liquidity so bob has BPT to remove liquidity
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        nftRouter.addLiquidityProportional(pool(), maxAmountsIn, DEFAULT_BPT_AMOUNT, false, bytes(""));
        vm.stopPrank();

        // Skip to fee has decayed to 5%
        skip(5 days);

        uint256 nftTokenId = 0;
        uint256[] memory minAmountsOut = [uint256(0), uint256(0)].toMemoryArray();

        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);

        vm.prank(bob);
        nftRouter.removeLiquidityProportional(nftTokenId, minAmountsOut, false);

        BaseVaultTest.Balances memory balancesAfter = getBalances(bob);

        // 5% exit fee.
        uint64 exitFeePercentage = 5e16;
        uint256 amountOut = DEFAULT_BPT_AMOUNT / 2;
        uint256 hookFee = amountOut.mulDown(exitFeePercentage);
        // Bob gets original liquidity with fee deducted.
        assertEq(
            balancesAfter.bobTokens[daiIdx] - balancesBefore.bobTokens[daiIdx],
            amountOut - hookFee,
            "bob's DAI amount is wrong"
        );
        assertEq(
            balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx],
            amountOut - hookFee,
            "bob's USDC amount is wrong"
        );

        // Pool balances decrease by amountOut, and receive hook fee.
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

        // Same happens with Vault balances: decrease by amountOut, and receive hook fee.
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

        // Hook balances remain unchanged.
        assertEq(balancesBefore.hookTokens[daiIdx], balancesAfter.hookTokens[daiIdx], "Hook's DAI amount is wrong");
        assertEq(balancesBefore.hookTokens[usdcIdx], balancesAfter.hookTokens[usdcIdx], "Hook's USDC amount is wrong");

        // Router should set all lp data to 0.
        assertEq(nftRouter.DEFAULT_BPT_AMOUNT(nftTokenId), 0, "DEFAULT_BPT_AMOUNT mapping should be 0");
        assertEq(nftRouter.startTime(nftTokenId), 0, "startTime mapping should be 0");
        assertEq(nftRouter.nftPool(nftTokenId), address(0), "pool mapping should be 0");

        assertEq(BalancerPoolToken(pool()).balanceOf(address(nftRouter)), 0, "NftRouter should hold no BPT");
        assertEq(balancesAfter.bobBpt, 0, "bob should not hold any BPT");
    }

    function testRemoveLiquidityFullDecay() public {
        // Add liquidity so bob has BPT to remove liquidity.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        nftRouter.addLiquidityProportional(pool(), maxAmountsIn, DEFAULT_BPT_AMOUNT, false, bytes(""));
        vm.stopPrank();

        // Skip to fee has decayed to 0.
        skip(13 days);

        uint256 nftTokenId = 0;
        uint256[] memory minAmountsOut = [uint256(0), uint256(0)].toMemoryArray();

        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);

        vm.prank(bob);
        nftRouter.removeLiquidityProportional(nftTokenId, minAmountsOut, false);

        BaseVaultTest.Balances memory balancesAfter = getBalances(bob);

        uint256 amountOut = DEFAULT_BPT_AMOUNT / 2;
        // Bob gets original liquidity with no fee applied because of full decay.
        assertEq(
            balancesAfter.bobTokens[daiIdx] - balancesBefore.bobTokens[daiIdx],
            amountOut,
            "bob's DAI amount is wrong"
        );
        assertEq(
            balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx],
            amountOut,
            "bob's USDC amount is wrong"
        );

        // Pool balances decrease by amountOut.
        assertEq(
            balancesBefore.poolTokens[daiIdx] - balancesAfter.poolTokens[daiIdx],
            amountOut,
            "Pool's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            amountOut,
            "Pool's USDC amount is wrong"
        );
        assertEq(balancesBefore.poolSupply - balancesAfter.poolSupply, 2 * amountOut, "BPT supply amount is wrong");

        // Same happens with Vault balances: decrease by amountOut.
        assertEq(
            balancesBefore.vaultTokens[daiIdx] - balancesAfter.vaultTokens[daiIdx],
            amountOut,
            "Vault's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            amountOut,
            "Vault's USDC amount is wrong"
        );

        // Hook balances remain unchanged.
        assertEq(balancesBefore.hookTokens[daiIdx], balancesAfter.hookTokens[daiIdx], "Hook's DAI amount is wrong");
        assertEq(balancesBefore.hookTokens[usdcIdx], balancesAfter.hookTokens[usdcIdx], "Hook's USDC amount is wrong");

        // Router should set all lp data to 0.
        assertEq(nftRouter.DEFAULT_BPT_AMOUNT(nftTokenId), 0, "DEFAULT_BPT_AMOUNT mapping should be 0");
        assertEq(nftRouter.startTime(nftTokenId), 0, "startTime mapping should be 0");
        assertEq(nftRouter.nftPool(nftTokenId), address(0), "pool mapping should be 0");

        assertEq(BalancerPoolToken(pool()).balanceOf(address(nftRouter)), 0, "NftRouter should hold no BPT");
        assertEq(balancesAfter.bobBpt, 0, "bob should not hold any BPT");
    }

    function testRemoveWithNonOwner() public {
        // Add liquidity so bob has BPT to remove liquidity.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        nftRouter.addLiquidityProportional(pool(), maxAmountsIn, DEFAULT_BPT_AMOUNT, false, bytes(""));
        vm.stopPrank();

        uint256 nftTokenId = 0;
        uint256[] memory minAmountsOut = [uint256(0), uint256(0)].toMemoryArray();

        // Remove fails because lp isn't the owner of the NFT.
        vm.expectRevert(
            abi.encodeWithSelector(NftLiquidityPositionExample.WithdrawalByNonOwner.selector, lp, bob, nftTokenId)
        );
        vm.prank(lp);
        nftRouter.removeLiquidityProportional(nftTokenId, minAmountsOut, false);
    }

    function testAddFromExternalRouter() public {
        // Add fails because it must be done via NftLiquidityPositionExample.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.expectRevert(abi.encodeWithSelector(NftLiquidityPositionExample.CannotUseExternalRouter.selector, router));
        vm.prank(bob);
        router.addLiquidityProportional(pool(), maxAmountsIn, DEFAULT_BPT_AMOUNT, false, bytes(""));
    }

    function testRemoveFromExternalRouter() public {
        uint256 amountOut = poolInitAmount() / 2;
        uint256[] memory minAmountsOut = [amountOut, amountOut].toMemoryArray();

        // Remove fails because it must be done via NftLiquidityPositionExample.
        vm.expectRevert(abi.encodeWithSelector(NftLiquidityPositionExample.CannotUseExternalRouter.selector, router));
        vm.prank(lp);
        router.removeLiquidityProportional(pool(), 2 * amountOut, minAmountsOut, false, bytes(""));
    }
}
