// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BufferRouterTest is BaseVaultTest {
    using FixedPoint for uint256;

    uint256 private constant _BUFFER_MINIMUM_TOTAL_SUPPLY = 1e4;
    uint256 private constant _WADAI_RATE = 2e18;
    uint256 private constant _DEFAULT_INPUT_AMOUNT = 1e18;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        waDAI.mockRate(_WADAI_RATE); // Just make it 2:1 for simplicity
    }

    function testInitializeBuffer() public {
        vm.prank(alice);
        uint256 issuedShares = bufferRouter.initializeBuffer(waDAI, 10e18, 100e18, 1e18);

        assertEq(vault.getBufferAsset(waDAI), waDAI.asset(), "Wrong asset");
        assertEq(vault.getBufferOwnerShares(waDAI, alice), issuedShares, "Wrong issued shares");
        assertEq(vault.getBufferTotalShares(waDAI), issuedShares + _BUFFER_MINIMUM_TOTAL_SUPPLY, "Wrong total shares");
    }

    function testInitializeBufferBelowMinShares() public {
        uint256 minIssuedShares = 10e18;
        uint256 inputAmount = 1e18;

        vm.prank(alice);
        vm.expectRevert(
            // Subtract min supply and rounding
            abi.encodeWithSelector(
                IVaultErrors.IssuedSharesBelowMin.selector,
                inputAmount + inputAmount.mulDown(_WADAI_RATE) - _BUFFER_MINIMUM_TOTAL_SUPPLY - 1,
                minIssuedShares
            )
        );
        bufferRouter.initializeBuffer(waDAI, inputAmount, inputAmount, minIssuedShares);
    }

    function testQueryInitializeBuffer__Fuzz(uint256 amountUnderlying, uint256 amountWrapped, uint256 rate) public {
        amountUnderlying = bound(amountUnderlying, 1e6, 100_000e18);
        amountWrapped = bound(amountWrapped, 1e6, 100_000e18);
        rate = bound(rate, 0.1e18, 10_000e18);

        waDAI.mockRate(rate);

        uint256 snapshotId = vm.snapshot();

        _prankStaticCall();
        uint256 expectedIssuedShares = bufferRouter.queryInitializeBuffer(waDAI, amountUnderlying, amountWrapped);

        vm.revertTo(snapshotId);

        vm.prank(alice);
        uint256 issuedShares = bufferRouter.initializeBuffer(
            waDAI,
            amountUnderlying,
            amountWrapped,
            expectedIssuedShares
        );

        assertEq(issuedShares, expectedIssuedShares, "Initialize buffer query mismatch");
    }

    function testAddLiquidityToBuffer() public {
        vm.prank(alice);
        uint256 initialShares = bufferRouter.initializeBuffer(waDAI, 1e18, 1e18, 0);

        uint256 inputAmount = 1e18;
        uint256 sharesToIssue = inputAmount + inputAmount.mulDown(_WADAI_RATE);
        uint256 inputAmountRoundUp = inputAmount + 1;

        vm.prank(bob);
        (uint256 actualAmountInUnderlying, uint256 actualAmountInWrapped) = bufferRouter.addLiquidityToBuffer(
            waDAI,
            inputAmountRoundUp,
            inputAmountRoundUp,
            sharesToIssue
        );

        assertEq(actualAmountInUnderlying, inputAmountRoundUp, "Wrong amount in underlying");
        assertEq(actualAmountInWrapped, inputAmountRoundUp, "Wrong amount in wrapped");
        assertEq(vault.getBufferOwnerShares(waDAI, bob), sharesToIssue, "Wrong issued shares");
        assertEq(
            vault.getBufferTotalShares(waDAI),
            initialShares + _BUFFER_MINIMUM_TOTAL_SUPPLY + sharesToIssue,
            "Wrong total shares"
        );
    }

    function testAddLiquidityToBufferAboveMaxAmountsInUnderlying() public {
        vm.prank(alice);
        bufferRouter.initializeBuffer(waDAI, 1e18, 1e18, 0);

        uint256 inputAmount = 1e18;
        uint256 sharesToIssue = inputAmount + inputAmount.mulDown(_WADAI_RATE);
        uint256 inputAmountRoundUp = inputAmount + 1;

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.AmountInAboveMax.selector,
                IERC20(waDAI.asset()),
                inputAmountRoundUp,
                inputAmount
            )
        );
        bufferRouter.addLiquidityToBuffer(waDAI, inputAmount, inputAmountRoundUp, sharesToIssue);
    }

    function testAddLiquidityToBufferAboveMaxAmountsInWrapped() public {
        vm.prank(alice);
        bufferRouter.initializeBuffer(waDAI, _DEFAULT_INPUT_AMOUNT, _DEFAULT_INPUT_AMOUNT, 0);

        uint256 inputAmount = _DEFAULT_INPUT_AMOUNT;
        uint256 sharesToIssue = inputAmount + inputAmount.mulDown(_WADAI_RATE);
        uint256 inputAmountRoundUp = inputAmount + 1;

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.AmountInAboveMax.selector,
                IERC20(waDAI),
                inputAmountRoundUp,
                inputAmount
            )
        );
        bufferRouter.addLiquidityToBuffer(waDAI, inputAmountRoundUp, inputAmount, sharesToIssue);
    }

    function testQueryAddLiquidityToBuffer__Fuzz(
        uint256 initAmountUnderlying,
        uint256 initAmountWrapped,
        uint256 expectedIssuedShares,
        uint256 rate
    ) public {
        initAmountUnderlying = bound(initAmountUnderlying, 1000e18, 100_000e18);
        initAmountWrapped = bound(initAmountWrapped, 100e18, 100_000e18);
        expectedIssuedShares = bound(expectedIssuedShares, 1e6, 100_000e18);

        rate = bound(rate, 0.1e18, 10_000e18);
        waDAI.mockRate(rate);

        vm.prank(alice);
        bufferRouter.initializeBuffer(waDAI, initAmountUnderlying, initAmountWrapped, 0);

        uint256 snapshotId = vm.snapshot();

        _prankStaticCall();
        (uint256 expectedAmountInUnderlying, uint256 expectedAmountInWrapped) = bufferRouter.queryAddLiquidityToBuffer(
            waDAI,
            expectedIssuedShares
        );

        vm.revertTo(snapshotId);

        vm.prank(bob);
        (uint256 actualAmountInUnderlying, uint256 actualAmountInWrapped) = bufferRouter.addLiquidityToBuffer(
            waDAI,
            expectedAmountInUnderlying,
            expectedAmountInWrapped,
            expectedIssuedShares
        );

        assertEq(actualAmountInUnderlying, expectedAmountInUnderlying, "Expected amount in underlying mismatch");
        assertEq(actualAmountInWrapped, expectedAmountInWrapped, "Expected amount in wrapped mismatch");
    }

    function testQueryRemoveLiquidityFromBuffer__Fuzz(
        uint256 initAmountUnderlying,
        uint256 initAmountWrapped,
        uint256 rate,
        uint256 sharesToRemove
    ) public {
        initAmountUnderlying = bound(initAmountUnderlying, 1000e18, 100_000e18);
        initAmountWrapped = bound(initAmountWrapped, 100e18, 100_000e18);

        rate = bound(rate, 0.1e18, 10_000e18);
        waDAI.mockRate(rate);

        vm.prank(alice);
        uint256 initialShares = bufferRouter.initializeBuffer(waDAI, initAmountUnderlying, initAmountWrapped, 0);
        sharesToRemove = bound(sharesToRemove, 1e6, initialShares);

        uint256 snapshotId = vm.snapshot();

        _prankStaticCall();
        (uint256 expectedAmountOutUnderlying, uint256 expectedAmountOutWrapped) = bufferRouter
            .queryRemoveLiquidityFromBuffer(waDAI, sharesToRemove);

        vm.revertTo(snapshotId);

        vm.prank(alice);
        (uint256 actualAmountOutUnderlying, uint256 actualAmountOutWrapped) = vault.removeLiquidityFromBuffer(
            waDAI,
            sharesToRemove,
            expectedAmountOutUnderlying,
            expectedAmountOutWrapped
        );

        assertEq(actualAmountOutUnderlying, expectedAmountOutUnderlying, "Expected amount out underlying mismatch");
        assertEq(actualAmountOutWrapped, expectedAmountOutWrapped, "Expected amount out wrapped mismatch");
    }
}
