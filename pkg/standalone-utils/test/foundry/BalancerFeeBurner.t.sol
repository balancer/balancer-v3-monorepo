// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IProtocolFeeSweeper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeSweeper.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IProtocolFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeBurner.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IBalancerFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IBalancerFeeBurner.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { ProtocolFeeSweeper } from "../../contracts/ProtocolFeeSweeper.sol";
import { BalancerFeeBurner } from "../../contracts/BalancerFeeBurner.sol";

contract BalancerFeeBurnerTest is BaseVaultTest {
    using SafeERC20 for IERC20;
    using ArrayHelpers for *;

    uint256 constant TEST_BURN_AMOUNT = 1e18;
    uint256 constant MIN_TARGET_TOKEN_AMOUNT = 1e18;
    uint256 constant ORDER_LIFETIME = 1 days;

    uint256 internal orderDeadline;

    IAuthentication internal feeBurnerAuth;
    IAuthentication internal feeSweeperAuth;

    IBalancerFeeBurner internal feeBurner;
    IProtocolFeeSweeper internal feeSweeper;

    address daiWethPool;
    address wethUsdcPool;

    uint256 daiIdx = 0;
    uint256 usdcIdx = 1;

    function setUp() public override {
        BaseVaultTest.setUp();

        feeSweeper = new ProtocolFeeSweeper(vault, alice);

        orderDeadline = block.timestamp + ORDER_LIFETIME;
        feeBurner = new BalancerFeeBurner(vault, feeSweeper, admin);

        feeBurnerAuth = IAuthentication(address(feeBurner));
        feeSweeperAuth = IAuthentication(address(feeSweeper));

        authorizer.grantRole(feeSweeperAuth.getActionId(IProtocolFeeSweeper.setFeeRecipient.selector), admin);
        authorizer.grantRole(feeSweeperAuth.getActionId(IProtocolFeeSweeper.setTargetToken.selector), admin);
        authorizer.grantRole(feeSweeperAuth.getActionId(IProtocolFeeSweeper.addProtocolFeeBurner.selector), admin);
        authorizer.grantRole(feeSweeperAuth.getActionId(IProtocolFeeSweeper.sweepProtocolFeesForToken.selector), admin);

        // Allow the fee sweeper to withdraw protocol fees.
        authorizer.grantRole(
            IAuthentication(address(feeController)).getActionId(
                IProtocolFeeController.withdrawProtocolFeesForToken.selector
            ),
            address(feeSweeper)
        );

        vm.prank(admin);
        feeSweeper.addProtocolFeeBurner(feeBurner);

        // Create dai -> weth -> usdc path. Standard `pool` has [dai, usdc].
        (daiWethPool, ) = _createPool([address(dai), address(weth)].toMemoryArray(), "pool");
        (wethUsdcPool, ) = _createPool([address(weth), address(usdc)].toMemoryArray(), "pool");

        approveForPool(IERC20(daiWethPool));
        approveForPool(IERC20(wethUsdcPool));

        vm.startPrank(lp);
        _initPool(daiWethPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        _initPool(wethUsdcPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();
    }

    function testSweepAndBurn() public {
        IBalancerFeeBurner.SwapPathStep[] memory steps = new IBalancerFeeBurner.SwapPathStep[](1);
        steps[0] = IBalancerFeeBurner.SwapPathStep({ pool: pool, tokenOut: usdc });

        Balances memory balancesBefore = getBalances();

        vm.prank(alice);
        feeBurner.setBurnPath(dai, steps);

        // Set up the sweeper to be able to burn.
        vm.startPrank(admin);
        feeSweeper.setTargetToken(usdc);

        // Put some fees in the Vault.
        vault.manualSetAggregateSwapFeeAmount(pool, dai, TEST_BURN_AMOUNT);

        vm.expectEmit();
        emit IProtocolFeeBurner.ProtocolFeeBurned(pool, dai, TEST_BURN_AMOUNT, usdc, TEST_BURN_AMOUNT, alice);

        feeSweeper.sweepProtocolFeesForToken(pool, dai, TEST_BURN_AMOUNT, orderDeadline, feeBurner);
        vm.stopPrank();

        Balances memory balancesAfter = getBalances();

        assertEq(
            balancesAfter.userTokens[daiIdx],
            balancesBefore.userTokens[daiIdx],
            "DAI balance should not change (feeSweeper)"
        );
        assertEq(
            balancesAfter.aliceTokens[usdcIdx],
            balancesBefore.aliceTokens[usdcIdx] + TEST_BURN_AMOUNT,
            "USDC balance should increase (alice)"
        );
        assertEq(
            balancesAfter.vaultTokens[daiIdx],
            balancesBefore.vaultTokens[daiIdx],
            "DAI balance should not change (vault)"
        );
        assertEq(
            balancesAfter.vaultTokens[usdcIdx],
            balancesBefore.vaultTokens[usdcIdx] - TEST_BURN_AMOUNT,
            "USDC balance should decrease (vault)"
        );

        assertEq(dai.balanceOf(address(feeBurner)), 0, "FeeBurner should not hold DAI");
        assertEq(usdc.balanceOf(address(feeBurner)), 0, "FeeBurner should not hold USDC");
    }

    function testBurnWithOneHop() external {
        vm.prank(alice);
        IERC20(address(dai)).transfer(address(feeSweeper), TEST_BURN_AMOUNT);

        IBalancerFeeBurner.SwapPathStep[] memory steps = new IBalancerFeeBurner.SwapPathStep[](1);
        steps[0] = IBalancerFeeBurner.SwapPathStep({ pool: pool, tokenOut: usdc });

        Balances memory balancesBefore = getBalances();

        vm.prank(alice);
        feeBurner.setBurnPath(dai, steps);

        vm.startPrank(address(feeSweeper));
        IERC20(address(dai)).forceApprove(address(feeBurner), TEST_BURN_AMOUNT);
        feeBurner.burn(address(0), dai, TEST_BURN_AMOUNT, usdc, MIN_TARGET_TOKEN_AMOUNT, alice, orderDeadline);
        vm.stopPrank();

        Balances memory balancesAfter = getBalances();

        assertEq(
            balancesAfter.userTokens[daiIdx],
            balancesBefore.userTokens[daiIdx] - TEST_BURN_AMOUNT,
            "DAI balance should decrease (feeSweeper)"
        );
        assertEq(
            balancesAfter.aliceTokens[usdcIdx],
            balancesBefore.aliceTokens[usdcIdx] + TEST_BURN_AMOUNT,
            "USDC balance should increase (alice)"
        );
        assertEq(
            balancesAfter.vaultTokens[daiIdx],
            balancesBefore.vaultTokens[daiIdx] + TEST_BURN_AMOUNT,
            "DAI balance should increase (vault)"
        );
        assertEq(
            balancesAfter.vaultTokens[usdcIdx],
            balancesBefore.vaultTokens[usdcIdx] - TEST_BURN_AMOUNT,
            "USDC balance should decrease (vault)"
        );

        assertEq(dai.balanceOf(address(feeBurner)), 0, "FeeBurner should not hold DAI");
        assertEq(usdc.balanceOf(address(feeBurner)), 0, "FeeBurner should not hold USDC");
    }

    function testBurnWithMultiHop() external {
        vm.prank(alice);
        IERC20(address(dai)).transfer(address(feeSweeper), TEST_BURN_AMOUNT);

        IBalancerFeeBurner.SwapPathStep[] memory steps = new IBalancerFeeBurner.SwapPathStep[](2);
        steps[0] = IBalancerFeeBurner.SwapPathStep({ pool: daiWethPool, tokenOut: weth });
        steps[1] = IBalancerFeeBurner.SwapPathStep({ pool: wethUsdcPool, tokenOut: usdc });

        Balances memory balancesBefore = getBalances();

        vm.prank(alice);
        feeBurner.setBurnPath(dai, steps);

        vm.startPrank(address(feeSweeper));
        IERC20(address(dai)).forceApprove(address(feeBurner), TEST_BURN_AMOUNT);
        feeBurner.burn(address(0), dai, TEST_BURN_AMOUNT, usdc, MIN_TARGET_TOKEN_AMOUNT, alice, orderDeadline);
        vm.stopPrank();

        Balances memory balancesAfter = getBalances();

        assertEq(
            balancesAfter.userTokens[daiIdx],
            balancesBefore.userTokens[daiIdx] - TEST_BURN_AMOUNT,
            "DAI balance should decrease (feeSweeper)"
        );
        assertEq(
            balancesAfter.aliceTokens[usdcIdx],
            balancesBefore.aliceTokens[usdcIdx] + TEST_BURN_AMOUNT,
            "USDC balance should increase (alice)"
        );
        assertEq(
            balancesAfter.vaultTokens[daiIdx],
            balancesBefore.vaultTokens[daiIdx] + TEST_BURN_AMOUNT,
            "DAI balance should increase (vault)"
        );
        assertEq(
            balancesAfter.vaultTokens[usdcIdx],
            balancesBefore.vaultTokens[usdcIdx] - TEST_BURN_AMOUNT,
            "USDC balance should decrease (vault)"
        );
        assertEq(dai.balanceOf(address(feeBurner)), 0, "FeeBurner should not hold DAI");
        assertEq(usdc.balanceOf(address(feeBurner)), 0, "FeeBurner should not hold USDC");
    }

    function testBurnRevertIfNotAuthorized() external {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeBurner.burn(address(0), dai, TEST_BURN_AMOUNT, usdc, MIN_TARGET_TOKEN_AMOUNT, alice, orderDeadline);
    }

    function testSetPathRevertIfNotAuthorized() external {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeBurner.setBurnPath(dai, new IBalancerFeeBurner.SwapPathStep[](0));
    }

    function testBurnRevertIfDeadlinePassed() external {
        vm.expectRevert(IProtocolFeeBurner.SwapDeadline.selector);

        vm.prank(address(feeSweeper));
        feeBurner.burn(address(0), dai, TEST_BURN_AMOUNT, usdc, MIN_TARGET_TOKEN_AMOUNT, alice, block.timestamp - 1);
    }

    function testBurnRevertIfOutLessThanMinAmount() external {
        vm.prank(alice);
        IERC20(address(dai)).transfer(address(feeSweeper), TEST_BURN_AMOUNT);

        IBalancerFeeBurner.SwapPathStep[] memory steps = new IBalancerFeeBurner.SwapPathStep[](1);
        steps[0] = IBalancerFeeBurner.SwapPathStep({ pool: pool, tokenOut: usdc });

        vm.prank(alice);
        feeBurner.setBurnPath(dai, steps);

        vm.startPrank(address(feeSweeper));
        IERC20(address(dai)).forceApprove(address(feeBurner), TEST_BURN_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, TEST_BURN_AMOUNT, TEST_BURN_AMOUNT + 1)
        );
        feeBurner.burn(address(0), dai, TEST_BURN_AMOUNT, usdc, TEST_BURN_AMOUNT + 1, alice, orderDeadline);
        vm.stopPrank();
    }

    function testBurnRevertIfLastPathStepNotTargetToken() external {
        IBalancerFeeBurner.SwapPathStep[] memory steps = new IBalancerFeeBurner.SwapPathStep[](1);
        steps[0] = IBalancerFeeBurner.SwapPathStep({ pool: pool, tokenOut: weth });

        vm.prank(alice);
        feeBurner.setBurnPath(dai, steps);

        vm.startPrank(address(feeSweeper));
        vm.expectRevert(IBalancerFeeBurner.TargetTokenOutMismatch.selector);
        feeBurner.burn(address(0), dai, TEST_BURN_AMOUNT, usdc, MIN_TARGET_TOKEN_AMOUNT, alice, orderDeadline);
        vm.stopPrank();
    }

    function testBurnHookRevertIfCallerNotVault() external {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        BalancerFeeBurner(address(feeBurner)).burnHook(
            IBalancerFeeBurner.BurnHookParams({
                pool: address(0),
                sender: address(0),
                feeToken: dai,
                feeTokenAmount: TEST_BURN_AMOUNT,
                targetToken: usdc,
                minAmountOut: MIN_TARGET_TOKEN_AMOUNT,
                recipient: alice,
                deadline: orderDeadline
            })
        );
    }

    function testGetBurnPathRevertIfPathNotExists() external {
        vm.expectRevert(IBalancerFeeBurner.BurnPathDoesNotExist.selector);
        feeBurner.getBurnPath(dai);
    }

    function testSetBurnPathIfSenderIsFeeRecipient() external {
        vm.prank(alice);
        _testSetBurnPath();
    }

    function testSetBurnPathIfSenderIsOwner() external {
        vm.prank(admin);
        _testSetBurnPath();
    }

    function testSetBurnPathDouble() external {
        IBalancerFeeBurner.SwapPathStep[] memory oldSteps = new IBalancerFeeBurner.SwapPathStep[](2);
        oldSteps[0] = IBalancerFeeBurner.SwapPathStep({ pool: daiWethPool, tokenOut: weth });
        oldSteps[1] = IBalancerFeeBurner.SwapPathStep({ pool: wethUsdcPool, tokenOut: usdc });

        vm.prank(alice);
        feeBurner.setBurnPath(dai, oldSteps);

        IBalancerFeeBurner.SwapPathStep[] memory newSteps = new IBalancerFeeBurner.SwapPathStep[](1);
        newSteps[0] = IBalancerFeeBurner.SwapPathStep({ pool: pool, tokenOut: usdc });

        vm.prank(alice);
        feeBurner.setBurnPath(dai, newSteps);

        IBalancerFeeBurner.SwapPathStep[] memory steps = feeBurner.getBurnPath(dai);
        assertEq(steps.length, newSteps.length);
        assertEq(steps[0].pool, newSteps[0].pool);
        assertEq(address(steps[0].tokenOut), address(newSteps[0].tokenOut));
    }

    function testSetBurnPathRevertIfNotAuthorized() external {
        IBalancerFeeBurner.SwapPathStep[] memory steps;

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeBurner.setBurnPath(dai, steps);
    }

    function getBalances() internal view returns (Balances memory) {
        IERC20[] memory tokens = new IERC20[](2);
        tokens[daiIdx] = dai;
        tokens[usdcIdx] = usdc;

        return getBalances(address(feeSweeper), tokens);
    }

    function _testSetBurnPath() internal {
        IBalancerFeeBurner.SwapPathStep[] memory steps = new IBalancerFeeBurner.SwapPathStep[](1);
        steps[0] = IBalancerFeeBurner.SwapPathStep({ pool: pool, tokenOut: usdc });

        feeBurner.setBurnPath(dai, steps);

        IBalancerFeeBurner.SwapPathStep[] memory path = feeBurner.getBurnPath(dai);
        assertEq(path.length, steps.length);
        assertEq(path[0].pool, steps[0].pool);
        assertEq(address(path[0].tokenOut), address(steps[0].tokenOut));
    }
}
