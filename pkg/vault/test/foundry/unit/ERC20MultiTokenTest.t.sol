// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";

import { ERC20MultiTokenMock } from "../../../contracts/test/ERC20MultiTokenMock.sol";
import { ERC20MultiToken } from "../../../contracts/token/ERC20MultiToken.sol";
import { BalancerPoolToken } from "../../../contracts/BalancerPoolToken.sol";
import { VaultContractsDeployer } from "../utils/VaultContractsDeployer.sol";

contract ERC20MultiTokenTest is Test, IERC20Errors, ERC20MultiToken, VaultContractsDeployer {
    address internal constant POOL = address(0x01);
    address internal constant OWNER = address(0x02);
    address internal constant OWNER2 = address(0x03);
    address internal constant SPENDER = address(0x04);
    uint256 internal constant DEFAULT_AMOUNT = 100;
    uint256 internal constant POOL_MINIMUM_TOTAL_SUPPLY = 1e6;

    ERC20MultiTokenMock token;

    function setUp() public {
        token = deployERC20MultiTokenMock();
    }

    function testBalanceOfWithZeroValue() public view {
        assertEq(token.balanceOf(POOL, OWNER), 0, "Unexpected balance");
    }

    function testTotalSupplyWithZeroValue() public view {
        assertEq(token.totalSupply(POOL), 0, "Unexpected total supply");
    }

    function testAllowanceForTokenContract() public view {
        assertEq(token.allowance(POOL, OWNER, address(token)), 0, "Unexpected allowance");
    }

    function testAllowanceForNotTokenContractWithZeroValue() public view {
        assertEq(token.allowance(POOL, OWNER, SPENDER), 0, "Unexpected allowance");
    }

    function testApprove() public {
        vm.expectEmit();
        emit ERC20MultiToken.Approval(POOL, OWNER, SPENDER, DEFAULT_AMOUNT);

        _approveWithBPTEmitApprovalMock(POOL, OWNER, SPENDER, DEFAULT_AMOUNT);

        assertEq(token.allowance(POOL, OWNER, SPENDER), DEFAULT_AMOUNT, "Unexpected allowance");
    }

    function testApproveRevertIfOwnerIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidApprover.selector, address(0x00)));
        token.manualApprove(POOL, ZERO_ADDRESS, SPENDER, DEFAULT_AMOUNT);
    }

    function testApproveRevertIfSpenderIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidSpender.selector, ZERO_ADDRESS));
        token.manualApprove(POOL, OWNER, ZERO_ADDRESS, DEFAULT_AMOUNT);
    }

    function testSpendAllowance() public {
        uint256 initialAllowance = DEFAULT_AMOUNT;
        uint256 remainingAllowance = 1;
        uint256 spendAmount = initialAllowance - remainingAllowance;

        _approveWithBPTEmitApprovalMock(POOL, OWNER, SPENDER, initialAllowance);

        vm.expectEmit();
        emit ERC20MultiToken.Approval(POOL, OWNER, SPENDER, remainingAllowance);
        vm.mockCall(
            POOL,
            abi.encodeCall(BalancerPoolToken.emitApproval, (OWNER, SPENDER, remainingAllowance)),
            bytes("")
        );
        token.manualSpendAllowance(POOL, OWNER, SPENDER, spendAmount);

        assertEq(token.allowance(POOL, OWNER, SPENDER), remainingAllowance, "Unexpected allowance");
    }

    function testSpendAllowanceWhenAllowanceIsMax() public {
        _approveWithBPTEmitApprovalMock(POOL, OWNER, SPENDER, type(uint256).max);
        assertEq(token.allowance(POOL, OWNER, SPENDER), type(uint256).max, "Unexpected allowance (emit approval)");

        token.manualSpendAllowance(POOL, OWNER, SPENDER, 1);
        assertEq(token.allowance(POOL, OWNER, SPENDER), type(uint256).max, "Unexpected allowance (manual spend)");
    }

    function testSpendAllowanceWhenOwnerIsSender() public {
        assertEq(token.allowance(POOL, OWNER, OWNER), type(uint256).max, "Unexpected allowance (no manual spend)");

        token.manualSpendAllowance(POOL, OWNER, OWNER, 1);
        assertEq(token.allowance(POOL, OWNER, OWNER), type(uint256).max, "Unexpected allowance (manual spend)");
    }

    function testSpendAllowanceRevertIfInsufficientAllowance() public {
        uint256 initialAllowance = DEFAULT_AMOUNT;
        uint256 spendAmount = initialAllowance + 1;

        _approveWithBPTEmitApprovalMock(POOL, OWNER, SPENDER, initialAllowance);

        vm.expectRevert(
            abi.encodeWithSelector(ERC20InsufficientAllowance.selector, SPENDER, initialAllowance, spendAmount)
        );
        token.manualSpendAllowance(POOL, OWNER, SPENDER, spendAmount);
    }

    function testQueryModeBalanceIncrease() public {
        // we prank here msg.sender to OWNER and tx.origin to address(0x00) to simulate a static call
        vm.prank(OWNER, address(0x00));
        token.manualQueryModeBalanceIncrease(POOL, OWNER, DEFAULT_AMOUNT);
        assertEq(token.balanceOf(POOL, OWNER), DEFAULT_AMOUNT, "Unexpected balance");
    }

    function testQueryModeBalanceIncreaseRevertIfCallIsNotStatic() public {
        // we prank here msg.sender and tx.origin to OWNER to simulate a non-static call
        vm.prank(OWNER, OWNER);
        vm.expectRevert(EVMCallModeHelpers.NotStaticCall.selector);
        token.manualQueryModeBalanceIncrease(POOL, OWNER, DEFAULT_AMOUNT);
    }

    function testMint() public {
        vm.expectEmit();
        emit ERC20MultiToken.Transfer(POOL, ZERO_ADDRESS, OWNER, POOL_MINIMUM_TOTAL_SUPPLY);
        _mintWithBPTEmitTransferMock(POOL, OWNER, POOL_MINIMUM_TOTAL_SUPPLY);

        assertEq(token.balanceOf(POOL, OWNER), POOL_MINIMUM_TOTAL_SUPPLY, "Unexpected balance");
        assertEq(token.totalSupply(POOL), POOL_MINIMUM_TOTAL_SUPPLY, "Unexpected total supply");
    }

    function testDoubleMintToCheckTotalSupply() public {
        uint256 firstMintAmount = POOL_MINIMUM_TOTAL_SUPPLY;
        uint256 secondMintAmount = DEFAULT_AMOUNT;

        _mintWithBPTEmitTransferMock(POOL, OWNER, firstMintAmount);

        assertEq(token.balanceOf(POOL, OWNER), firstMintAmount, "Unexpected balance (first)");
        assertEq(token.totalSupply(POOL), firstMintAmount, "Unexpected total supply (first)");

        _mintWithBPTEmitTransferMock(POOL, OWNER2, secondMintAmount);
        assertEq(token.balanceOf(POOL, OWNER2), secondMintAmount, "Unexpected balance (second)");
        assertEq(token.totalSupply(POOL), firstMintAmount + secondMintAmount, "Unexpected total supply (second)");
    }

    function testMintRevertIfToIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidReceiver.selector, ZERO_ADDRESS));
        token.manualMint(POOL, ZERO_ADDRESS, DEFAULT_AMOUNT);
    }

    function testMintRevertIfTotalSupplyIsLessThanMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(PoolTotalSupplyTooLow.selector, POOL_MINIMUM_TOTAL_SUPPLY - 1));
        token.manualMint(POOL, OWNER, POOL_MINIMUM_TOTAL_SUPPLY - 1);
    }

    function testMintMinimumSupplyReserve() public {
        vm.expectEmit();
        emit ERC20MultiToken.Transfer(POOL, ZERO_ADDRESS, ZERO_ADDRESS, POOL_MINIMUM_TOTAL_SUPPLY);
        vm.mockCall(
            POOL,
            abi.encodeCall(BalancerPoolToken.emitTransfer, (ZERO_ADDRESS, ZERO_ADDRESS, POOL_MINIMUM_TOTAL_SUPPLY)),
            bytes("")
        );
        token.manualMintMinimumSupplyReserve(POOL);

        assertEq(token.balanceOf(POOL, ZERO_ADDRESS), POOL_MINIMUM_TOTAL_SUPPLY, "Unexpected balance");
        assertEq(token.totalSupply(POOL), POOL_MINIMUM_TOTAL_SUPPLY, "Unexpected total supply");
    }

    function testBurn() public {
        uint256 burnAmount = 1;
        uint256 balanceAfterBurn = POOL_MINIMUM_TOTAL_SUPPLY;
        uint256 mintAmount = balanceAfterBurn + burnAmount;

        _mintWithBPTEmitTransferMock(POOL, OWNER, mintAmount);

        vm.expectEmit();
        emit ERC20MultiToken.Transfer(POOL, OWNER, ZERO_ADDRESS, burnAmount);
        _burnWithBPTEmitTransferMock(POOL, OWNER, burnAmount);

        assertEq(token.balanceOf(POOL, OWNER), balanceAfterBurn, "Unexpected balance");
        assertEq(token.totalSupply(POOL), balanceAfterBurn, "Unexpected total supply");
    }

    function testDoubleBurnToCheckTotalSupply() public {
        uint256 firstMintAmount = token.getPoolMinimumTotalSupply();
        uint256 secondMintAmount = DEFAULT_AMOUNT;
        uint256 burnAmount = 50;

        _mintWithBPTEmitTransferMock(POOL, OWNER, firstMintAmount);
        _mintWithBPTEmitTransferMock(POOL, OWNER2, secondMintAmount);

        _burnWithBPTEmitTransferMock(POOL, OWNER, burnAmount);
        assertEq(token.balanceOf(POOL, OWNER), firstMintAmount - burnAmount, "Unexpected balance (first)");

        uint256 totalSupplyAfterFirstBurn = (firstMintAmount + secondMintAmount) - burnAmount;
        assertEq(token.totalSupply(POOL), totalSupplyAfterFirstBurn, "Unexpected total supply (first)");

        uint256 totalSupplyAfterSecondBurn = totalSupplyAfterFirstBurn - burnAmount;
        _burnWithBPTEmitTransferMock(POOL, OWNER2, burnAmount);
        assertEq(token.balanceOf(POOL, OWNER2), secondMintAmount - burnAmount, "Unexpected balance (second)");
        assertEq(token.totalSupply(POOL), totalSupplyAfterSecondBurn, "Unexpected total supply (second)");
    }

    function testBurnRevertIfFromIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidSender.selector, ZERO_ADDRESS));
        token.manualBurn(POOL, ZERO_ADDRESS, DEFAULT_AMOUNT);
    }

    function testBurnRevertIfTotalSupplyIsLessThanMinimum() public {
        uint256 burnAmount = 1;

        _mintWithBPTEmitTransferMock(POOL, OWNER, POOL_MINIMUM_TOTAL_SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(PoolTotalSupplyTooLow.selector, POOL_MINIMUM_TOTAL_SUPPLY - burnAmount));
        token.manualBurn(POOL, OWNER, burnAmount);
    }

    function testBurnRevertIfInsufficientBalance() public {
        uint256 mintAmount = token.getPoolMinimumTotalSupply();
        uint256 burnAmount = mintAmount + 1;

        _mintWithBPTEmitTransferMock(POOL, OWNER, mintAmount);

        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, OWNER, mintAmount, burnAmount));
        token.manualBurn(POOL, OWNER, burnAmount);
    }

    function testTransfer() public {
        _mintWithBPTEmitTransferMock(POOL, OWNER, POOL_MINIMUM_TOTAL_SUPPLY);

        vm.mockCall(
            POOL,
            abi.encodeCall(BalancerPoolToken.emitTransfer, (OWNER, OWNER2, POOL_MINIMUM_TOTAL_SUPPLY)),
            bytes("")
        );
        vm.expectEmit();
        emit ERC20MultiToken.Transfer(POOL, OWNER, OWNER2, POOL_MINIMUM_TOTAL_SUPPLY);
        token.manualTransfer(POOL, OWNER, OWNER2, POOL_MINIMUM_TOTAL_SUPPLY);

        assertEq(token.balanceOf(POOL, OWNER), 0, "Unexpected balance (owner)");
        assertEq(token.balanceOf(POOL, OWNER2), POOL_MINIMUM_TOTAL_SUPPLY, "Unexpected balance (owner2)");
    }

    function testTransferRevertIfFromIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidSender.selector, ZERO_ADDRESS));
        token.manualTransfer(POOL, ZERO_ADDRESS, OWNER, 100);
    }

    function testTransferRevertIfToIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidReceiver.selector, ZERO_ADDRESS));
        token.manualTransfer(POOL, OWNER, ZERO_ADDRESS, 100);
    }

    function testTransferRevertIfInsufficientBalance() public {
        uint256 transferAmount = POOL_MINIMUM_TOTAL_SUPPLY + 1;

        _mintWithBPTEmitTransferMock(POOL, OWNER, POOL_MINIMUM_TOTAL_SUPPLY);

        vm.expectRevert(
            abi.encodeWithSelector(ERC20InsufficientBalance.selector, OWNER, POOL_MINIMUM_TOTAL_SUPPLY, transferAmount)
        );
        token.manualTransfer(POOL, OWNER, OWNER2, transferAmount);
    }

    function _approveWithBPTEmitApprovalMock(address pool, address owner, address spender, uint256 amount) internal {
        vm.mockCall(pool, abi.encodeCall(BalancerPoolToken.emitApproval, (owner, spender, amount)), bytes(""));
        token.manualApprove(pool, owner, spender, amount);
    }

    function _mintWithBPTEmitTransferMock(address pool, address owner, uint256 amount) internal {
        vm.mockCall(pool, abi.encodeCall(BalancerPoolToken.emitTransfer, (ZERO_ADDRESS, owner, amount)), bytes(""));
        token.manualMint(pool, owner, amount);
    }

    function _burnWithBPTEmitTransferMock(address pool, address from, uint256 amount) internal {
        vm.mockCall(pool, abi.encodeCall(BalancerPoolToken.emitTransfer, (from, ZERO_ADDRESS, amount)), bytes(""));
        token.manualBurn(pool, from, amount);
    }
}
