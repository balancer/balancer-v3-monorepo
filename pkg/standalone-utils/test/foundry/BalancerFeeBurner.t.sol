// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IProtocolFeeSweeper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeSweeper.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IProtocolFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeBurner.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IBalancerFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IBalancerFeeBurner.sol";
import { SwapPathStep } from "@balancer-labs/v3-interfaces/contracts/vault/BatchRouterTypes.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { ProtocolFeeSweeper } from "../../contracts/ProtocolFeeSweeper.sol";
import { BalancerFeeBurner } from "../../contracts/BalancerFeeBurner.sol";

contract BalancerFeeBurnerTest is BaseVaultTest {
    using SafeERC20 for IERC20;
    using ArrayHelpers for *;

    uint256 constant DELTA = 10;
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
    address daiUsdcPool;

    // Index in getBalances() result arrays
    uint256 daiIdx = 0;
    uint256 usdcIdx = 1;
    uint256 waDaiIdx = 2;
    uint256 waWethIdx = 3;
    uint256 waUsdcIdx = 4;

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

        // Allow the admin to withdraw protocol fees.
        authorizer.grantRole(
            IAuthentication(address(feeController)).getActionId(IProtocolFeeController.withdrawProtocolFees.selector),
            address(admin)
        );
        authorizer.grantRole(
            IAuthentication(address(feeController)).getActionId(
                IProtocolFeeController.withdrawProtocolFeesForToken.selector
            ),
            address(admin)
        );

        vm.prank(admin);
        feeSweeper.addProtocolFeeBurner(feeBurner);

        // Create dai -> weth -> usdc path. Standard `pool` has [dai, usdc].
        (daiWethPool, ) = _createPool([address(dai), address(weth)].toMemoryArray(), "pool");
        (wethUsdcPool, ) = _createPool([address(weth), address(usdc)].toMemoryArray(), "pool");
        daiUsdcPool = pool;

        approveForPool(IERC20(daiWethPool));
        approveForPool(IERC20(wethUsdcPool));

        vm.startPrank(lp);
        _initPool(daiWethPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        _initPool(wethUsdcPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        bufferRouter.initializeBuffer(waDAI, poolInitAmount, 0, 0);
        bufferRouter.initializeBuffer(waUSDC, poolInitAmount, 0, 0);
        vm.stopPrank();
    }

    function testSweepAndBurn() public {
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: daiUsdcPool, tokenOut: usdc, isBuffer: false });

        Balances memory balancesBefore = getBalances();

        vm.prank(alice);
        feeBurner.setBurnPath(dai, steps);

        // Set up the sweeper to be able to burn.
        vm.prank(admin);
        feeSweeper.setTargetToken(usdc);

        // Put some fees in the Vault.
        vault.manualSetAggregateSwapFeeAmount(daiUsdcPool, dai, TEST_BURN_AMOUNT);
        feeController.collectAggregateFees(daiUsdcPool);

        // Also need to withdraw them to the sweeper.
        vm.prank(admin);
        feeController.withdrawProtocolFees(daiUsdcPool, address(feeSweeper));

        vm.expectEmit();
        emit IProtocolFeeBurner.ProtocolFeeBurned(dai, TEST_BURN_AMOUNT, usdc, TEST_BURN_AMOUNT, alice);

        vm.prank(admin);
        feeSweeper.sweepProtocolFeesForToken(dai, TEST_BURN_AMOUNT, 0, orderDeadline, feeBurner);

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

        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: daiUsdcPool, tokenOut: usdc, isBuffer: false });

        Balances memory balancesBefore = getBalances();

        vm.prank(alice);
        feeBurner.setBurnPath(dai, steps);

        vm.startPrank(address(feeSweeper));
        IERC20(address(dai)).forceApprove(address(feeBurner), TEST_BURN_AMOUNT);
        feeBurner.burn(dai, TEST_BURN_AMOUNT, usdc, MIN_TARGET_TOKEN_AMOUNT, alice, orderDeadline);
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

        SwapPathStep[] memory steps = new SwapPathStep[](2);
        steps[0] = SwapPathStep({ pool: daiWethPool, tokenOut: weth, isBuffer: false });
        steps[1] = SwapPathStep({ pool: wethUsdcPool, tokenOut: usdc, isBuffer: false });

        Balances memory balancesBefore = getBalances();

        vm.prank(alice);
        feeBurner.setBurnPath(dai, steps);

        vm.startPrank(address(feeSweeper));
        IERC20(address(dai)).forceApprove(address(feeBurner), TEST_BURN_AMOUNT);
        feeBurner.burn(dai, TEST_BURN_AMOUNT, usdc, MIN_TARGET_TOKEN_AMOUNT, alice, orderDeadline);
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

    function testBurnWrap() external {
        vm.prank(alice);
        IERC20(address(dai)).transfer(address(feeSweeper), TEST_BURN_AMOUNT);

        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });

        Balances memory balancesBefore = getBalances();

        vm.prank(alice);
        feeBurner.setBurnPath(dai, steps);

        uint256 snapshot = vm.snapshotState();
        uint256 amountOut = _vaultPreviewDeposit(waDAI, TEST_BURN_AMOUNT);
        vm.revertToState(snapshot);

        vm.startPrank(address(feeSweeper));
        IERC20(address(dai)).forceApprove(address(feeBurner), TEST_BURN_AMOUNT);

        feeBurner.burn(dai, TEST_BURN_AMOUNT, waDAI, amountOut, alice, orderDeadline);
        vm.stopPrank();

        Balances memory balancesAfter = getBalances();

        assertEq(
            balancesAfter.userTokens[daiIdx],
            balancesBefore.userTokens[daiIdx] - TEST_BURN_AMOUNT,
            "DAI balance should decrease (feeSweeper)"
        );
        assertEq(
            balancesAfter.aliceTokens[waDaiIdx],
            balancesBefore.aliceTokens[waDaiIdx] + amountOut,
            "waDAI balance should increase (alice)"
        );

        assertEq(waDAI.balanceOf(address(feeBurner)), 0, "FeeBurner should not hold waDAI");
        assertEq(dai.balanceOf(address(feeBurner)), 0, "FeeBurner should not hold DAI");
    }

    function testBurnUnwrap() external {
        vm.prank(alice);
        IERC20(address(waDAI)).transfer(address(feeSweeper), TEST_BURN_AMOUNT);

        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: address(waDAI), tokenOut: dai, isBuffer: true });

        Balances memory balancesBefore = getBalances();

        vm.prank(alice);
        feeBurner.setBurnPath(waDAI, steps);

        uint256 snapshot = vm.snapshotState();
        uint256 amountOut = _vaultPreviewRedeem(waDAI, TEST_BURN_AMOUNT);
        vm.revertToState(snapshot);

        vm.startPrank(address(feeSweeper));
        IERC20(address(waDAI)).forceApprove(address(feeBurner), TEST_BURN_AMOUNT);

        feeBurner.burn(waDAI, TEST_BURN_AMOUNT, dai, amountOut, alice, orderDeadline);
        vm.stopPrank();

        Balances memory balancesAfter = getBalances();

        assertEq(
            balancesAfter.userTokens[waDaiIdx],
            balancesBefore.userTokens[waDaiIdx] - TEST_BURN_AMOUNT,
            "waDAI balance should decrease (feeSweeper)"
        );
        assertEq(
            balancesAfter.aliceTokens[daiIdx],
            balancesBefore.aliceTokens[daiIdx] + amountOut,
            "DAI balance should increase (alice)"
        );
        assertEq(
            balancesAfter.vaultTokens[waDaiIdx],
            balancesBefore.vaultTokens[waDaiIdx] + TEST_BURN_AMOUNT,
            "waDAI balance should increase (vault)"
        );
        assertEq(
            balancesAfter.vaultTokens[daiIdx],
            balancesBefore.vaultTokens[daiIdx] - amountOut,
            "DAI balance should decrease (vault)"
        );

        assertEq(waDAI.balanceOf(address(feeBurner)), 0, "FeeBurner should not hold waDAI");
        assertEq(dai.balanceOf(address(feeBurner)), 0, "FeeBurner should not hold DAI");
    }

    function testBurnUnwrapWrap() external {
        vm.prank(alice);
        IERC20(address(waDAI)).transfer(address(feeSweeper), TEST_BURN_AMOUNT);

        SwapPathStep[] memory steps = new SwapPathStep[](2);
        steps[0] = SwapPathStep({ pool: address(waDAI), tokenOut: dai, isBuffer: true });
        steps[1] = SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });

        Balances memory balancesBefore = getBalances();

        vm.prank(alice);
        feeBurner.setBurnPath(waDAI, steps);

        vm.startPrank(address(feeSweeper));
        IERC20(address(waDAI)).forceApprove(address(feeBurner), TEST_BURN_AMOUNT);

        uint256 minAmountOut = TEST_BURN_AMOUNT - DELTA;
        feeBurner.burn(waDAI, TEST_BURN_AMOUNT, waDAI, minAmountOut, alice, orderDeadline);
        vm.stopPrank();

        Balances memory balancesAfter = getBalances();

        assertEq(
            balancesAfter.userTokens[waDaiIdx],
            balancesBefore.userTokens[waDaiIdx] - TEST_BURN_AMOUNT,
            "waDAI balance should decrease (feeSweeper)"
        );
        assertApproxEqAbs(
            balancesAfter.aliceTokens[waDaiIdx],
            balancesBefore.aliceTokens[waDaiIdx] + TEST_BURN_AMOUNT,
            DELTA,
            "DAI balance should increase (alice)"
        );
        assertApproxEqAbs(
            balancesAfter.vaultTokens[waDaiIdx],
            balancesBefore.vaultTokens[waDaiIdx],
            DELTA,
            "waDAI balance should not change (vault)"
        );

        assertEq(waDAI.balanceOf(address(feeBurner)), 0, "FeeBurner should not hold waDAI");
        assertEq(dai.balanceOf(address(feeBurner)), 0, "FeeBurner should not hold DAI");
    }

    function testBurnUnwrapSwapWrap() external {
        vm.prank(alice);
        IERC20(address(waDAI)).transfer(address(feeSweeper), TEST_BURN_AMOUNT);

        SwapPathStep[] memory steps = new SwapPathStep[](3);
        steps[0] = SwapPathStep({ pool: address(waDAI), tokenOut: dai, isBuffer: true });
        steps[1] = SwapPathStep({ pool: daiUsdcPool, tokenOut: usdc, isBuffer: false });
        steps[2] = SwapPathStep({ pool: address(waUSDC), tokenOut: waUSDC, isBuffer: true });

        Balances memory balancesBefore = getBalances();

        vm.prank(alice);
        feeBurner.setBurnPath(waDAI, steps);

        uint256 snapshot = vm.snapshotState();
        uint256 daiAmountOut = _vaultPreviewRedeem(waDAI, TEST_BURN_AMOUNT);
        uint256 amountOut = _vaultPreviewDeposit(waUSDC, daiAmountOut);
        vm.revertToState(snapshot);

        vm.startPrank(address(feeSweeper));
        IERC20(address(waDAI)).forceApprove(address(feeBurner), TEST_BURN_AMOUNT);

        feeBurner.burn(waDAI, TEST_BURN_AMOUNT, waUSDC, amountOut, alice, orderDeadline);
        vm.stopPrank();

        Balances memory balancesAfter = getBalances();

        assertEq(
            balancesAfter.userTokens[waDaiIdx],
            balancesBefore.userTokens[waDaiIdx] - TEST_BURN_AMOUNT,
            "waDAI balance should decrease (feeSweeper)"
        );
        assertEq(
            balancesAfter.aliceTokens[waUsdcIdx],
            balancesBefore.aliceTokens[waUsdcIdx] + amountOut,
            "USDC balance should increase (alice)"
        );

        assertEq(waDAI.balanceOf(address(feeBurner)), 0, "FeeBurner should not hold waDAI");
        assertEq(waUSDC.balanceOf(address(feeBurner)), 0, "FeeBurner should not hold DAI");
    }

    function testBurnRevertIfNotAuthorized() external {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeBurner.burn(dai, TEST_BURN_AMOUNT, usdc, MIN_TARGET_TOKEN_AMOUNT, alice, orderDeadline);
    }

    function testSetPathRevertIfNotAuthorized() external {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeBurner.setBurnPath(dai, new SwapPathStep[](0));
    }

    function testBurnRevertIfDeadlinePassed() external {
        vm.expectRevert(IProtocolFeeBurner.SwapDeadline.selector);

        vm.prank(address(feeSweeper));
        feeBurner.burn(dai, TEST_BURN_AMOUNT, usdc, MIN_TARGET_TOKEN_AMOUNT, alice, block.timestamp - 1);
    }

    function testBurnRevertIfOutLessThanMinAmount() external {
        vm.prank(alice);
        IERC20(address(dai)).transfer(address(feeSweeper), TEST_BURN_AMOUNT);

        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: daiUsdcPool, tokenOut: usdc, isBuffer: false });

        vm.prank(alice);
        feeBurner.setBurnPath(dai, steps);

        vm.startPrank(address(feeSweeper));
        IERC20(address(dai)).forceApprove(address(feeBurner), TEST_BURN_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, TEST_BURN_AMOUNT, TEST_BURN_AMOUNT + 1)
        );
        feeBurner.burn(dai, TEST_BURN_AMOUNT, usdc, TEST_BURN_AMOUNT + 1, alice, orderDeadline);
        vm.stopPrank();
    }

    function testBurnRevertIfLastPathStepNotTargetToken() external {
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: daiUsdcPool, tokenOut: usdc, isBuffer: false });

        vm.prank(alice);
        feeBurner.setBurnPath(dai, steps);

        vm.startPrank(address(feeSweeper));
        vm.expectRevert(IBalancerFeeBurner.TargetTokenOutMismatch.selector);
        feeBurner.burn(dai, TEST_BURN_AMOUNT, weth, MIN_TARGET_TOKEN_AMOUNT, alice, orderDeadline);
        vm.stopPrank();
    }

    function testBurnHookRevertIfCallerNotVault() external {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        BalancerFeeBurner(address(feeBurner)).burnHook(
            IBalancerFeeBurner.BurnHookParams({
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
        SwapPathStep[] memory oldSteps = new SwapPathStep[](2);
        oldSteps[0] = SwapPathStep({ pool: daiWethPool, tokenOut: weth, isBuffer: false });
        oldSteps[1] = SwapPathStep({ pool: wethUsdcPool, tokenOut: usdc, isBuffer: false });

        vm.prank(alice);
        feeBurner.setBurnPath(dai, oldSteps);

        SwapPathStep[] memory newSteps = new SwapPathStep[](1);
        newSteps[0] = SwapPathStep({ pool: daiUsdcPool, tokenOut: usdc, isBuffer: false });

        vm.prank(alice);
        feeBurner.setBurnPath(dai, newSteps);

        SwapPathStep[] memory steps = feeBurner.getBurnPath(dai);
        assertEq(steps.length, newSteps.length);
        assertEq(steps[0].pool, newSteps[0].pool);
        assertEq(address(steps[0].tokenOut), address(newSteps[0].tokenOut));
    }

    function testSetBurnPathRevertIfNotAuthorized() external {
        SwapPathStep[] memory steps;

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeBurner.setBurnPath(dai, steps);
    }

    function testSetBurnPathRevertIfInvalidBufferNotInitialized() external {
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: address(0x1234), tokenOut: dai, isBuffer: true });

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IBalancerFeeBurner.BufferNotInitialized.selector, address(0x1234)));
        feeBurner.setBurnPath(dai, steps);
    }

    function testSetBurnPathRevertIfInvalidTokenIn() external {
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: daiUsdcPool, tokenOut: usdc, isBuffer: false });

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IBalancerFeeBurner.TokenDoesNotExistInPool.selector, weth, 0));
        feeBurner.setBurnPath(weth, steps);
    }

    function testSetBurnPathRevertIfInvalidTokenOut() external {
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: daiUsdcPool, tokenOut: weth, isBuffer: false });

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IBalancerFeeBurner.TokenDoesNotExistInPool.selector, weth, 0));
        feeBurner.setBurnPath(dai, steps);
    }

    function testSetBurnPathRevertIfInvalidBufferUnwrapTokenOut() external {
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IBalancerFeeBurner.InvalidBufferTokenOut.selector, waDAI, 0));
        feeBurner.setBurnPath(waDAI, steps);
    }

    function testSetBurnPathRevertIfInvalidBufferWrapTokenOut() external {
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: address(waDAI), tokenOut: dai, isBuffer: true });

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IBalancerFeeBurner.InvalidBufferTokenOut.selector, dai, 0));
        feeBurner.setBurnPath(dai, steps);
    }

    function getBalances() internal view returns (Balances memory) {
        IERC20[] memory tokens = new IERC20[](5);
        tokens[daiIdx] = dai;
        tokens[usdcIdx] = usdc;
        tokens[waDaiIdx] = waDAI;
        tokens[waWethIdx] = waWETH;
        tokens[waUsdcIdx] = waUSDC;

        return getBalances(address(feeSweeper), tokens);
    }

    function _testSetBurnPath() internal {
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: daiUsdcPool, tokenOut: usdc, isBuffer: false });

        feeBurner.setBurnPath(dai, steps);

        SwapPathStep[] memory path = feeBurner.getBurnPath(dai);
        assertEq(path.length, steps.length);
        assertEq(path[0].pool, steps[0].pool);
        assertEq(address(path[0].tokenOut), address(steps[0].tokenOut));
    }
}
