// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { PoolSwapParams, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { ICowRouter } from "@balancer-labs/v3-interfaces/contracts/pool-cow/ICowRouter.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseCowTest } from "./utils/BaseCowTest.sol";
import { CowRouter } from "../../contracts/CowRouter.sol";

contract CowRouterTest is BaseCowTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 private constant _MIN_TRADE_AMOUNT = 1e6;

    function setUp() public override {
        vaultMockMinTradeAmount = _MIN_TRADE_AMOUNT;
        super.setUp();

        // Alice representes CoW Settlement.
        authorizer.grantRole(
            CowRouter(address(cowRouter)).getActionId(ICowRouter.swapExactInAndDonateSurplus.selector),
            alice
        );
        authorizer.grantRole(
            CowRouter(address(cowRouter)).getActionId(ICowRouter.swapExactOutAndDonateSurplus.selector),
            alice
        );
        authorizer.grantRole(CowRouter(address(cowRouter)).getActionId(ICowRouter.donate.selector), alice);
    }

    /********************************************************
                  swapExactInAndDonateSurplus()
    ********************************************************/

    function testSwapExactInAndDonateSurplusIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        cowRouter.swapExactInAndDonateSurplus(
            pool,
            dai,
            usdc,
            1e18,
            0,
            type(uint32).max,
            new uint256[](2),
            new uint256[](2),
            bytes("")
        );
    }

    function testSwapExactInAndDonateSurplusLimit() public {
        // 1% protocol fee percentage.
        uint256 protocolFeePercentage = 1e16;
        uint256 donationDai = DEFAULT_AMOUNT / 10;
        uint256 donationUsdc = DEFAULT_AMOUNT / 10;
        uint256 daiSwapAmountIn = DEFAULT_AMOUNT / 10;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (uint256[] memory donationAmounts, , , uint256[] memory transferAmountHints) = _getDonationAndFees(
            donationDai,
            donationUsdc,
            0,
            protocolFeePercentage
        );

        uint256 expectedSwapAmountOut = _calculateAmountOutSwapExactIn(daiSwapAmountIn);

        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, expectedSwapAmountOut, expectedSwapAmountOut + 1)
        );
        vm.prank(alice);
        // The swap reverts because the swap limit is 1 wei higher than `expectedSwapAmountOut`.
        cowRouter.swapExactInAndDonateSurplus(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            expectedSwapAmountOut + 1,
            type(uint32).max,
            donationAmounts,
            transferAmountHints,
            bytes("")
        );
    }

    function testSwapExactInAndDonateSurplusDeadline() public {
        // 1% protocol fee percentage.
        uint256 protocolFeePercentage = 1e16;
        uint256 donationDai = DEFAULT_AMOUNT / 10;
        uint256 donationUsdc = DEFAULT_AMOUNT / 10;
        uint256 daiSwapAmountIn = DEFAULT_AMOUNT / 10;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (uint256[] memory donationAmounts, , , uint256[] memory transferAmountHints) = _getDonationAndFees(
            donationDai,
            donationUsdc,
            0,
            protocolFeePercentage
        );

        vm.expectRevert(ICowRouter.SwapDeadline.selector);
        vm.prank(alice);
        // Since the blocknumber is bigger than the deadline, it should revert.
        uint256 deadline = block.number + 100;
        vm.warp(deadline + 1);
        cowRouter.swapExactInAndDonateSurplus(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            0,
            deadline,
            donationAmounts,
            transferAmountHints,
            bytes("")
        );
    }

    function testSwapExactInAndDonateSurplusEmptyDonation() public {
        // 1% protocol fee percentage.
        uint256 protocolFeePercentage = 1e16;
        uint256 donationDai = 0;
        uint256 donationUsdc = 0;
        uint256 daiSwapAmountIn = DEFAULT_AMOUNT / 10;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (
            uint256[] memory donationAmounts,
            uint256[] memory expectedProtocolFees,
            uint256[] memory donationAfterFees,
            uint256[] memory transferAmountHints
        ) = _getDonationAndFees(donationDai, donationUsdc, daiSwapAmountIn, protocolFeePercentage);

        uint256 expectedSwapAmountOut = _calculateAmountOutSwapExactIn(daiSwapAmountIn);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        // Should not revert, since there's no minimum limit in the donation.
        vm.startPrank(alice);
        dai.transfer(address(vault), transferAmountHints[daiIdx]);
        // Does not transfer USDC, since donation is 0 and the swap only requires DAI.

        vm.expectEmit();
        emit ICowRouter.CoWSwapAndDonation(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            expectedSwapAmountOut,
            donationAfterFees,
            expectedProtocolFees,
            bytes("")
        );
        cowRouter.swapExactInAndDonateSurplus(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            0,
            type(uint32).max,
            donationAmounts,
            transferAmountHints,
            bytes("")
        );
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(cowRouter));

        _checkBalancesAfterSwapAndDonation(
            balancesBefore,
            balancesAfter,
            expectedProtocolFees,
            donationAmounts,
            daiSwapAmountIn,
            expectedSwapAmountOut,
            0
        );
    }

    function testSwapExactInAndDonateSurplusEmptySwap() public {
        // 1% protocol fee percentage.
        uint256 protocolFeePercentage = 1e16;
        uint256 donationDai = DEFAULT_AMOUNT / 10;
        uint256 donationUsdc = DEFAULT_AMOUNT / 10;
        uint256 daiSwapAmountIn = 0;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (uint256[] memory donationAmounts, , , uint256[] memory transferAmountHints) = _getDonationAndFees(
            donationDai,
            donationUsdc,
            0,
            protocolFeePercentage
        );

        // Should revert, since swap amount cannot be zero.
        vm.expectRevert(IVaultErrors.AmountGivenZero.selector);
        vm.prank(alice);
        cowRouter.swapExactInAndDonateSurplus(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            0,
            type(uint32).max,
            donationAmounts,
            transferAmountHints,
            bytes("")
        );
    }

    function testSwapExactInAndDonateSurplusBelowMinSwap() public {
        // 1% protocol fee percentage.
        uint256 protocolFeePercentage = 1e16;
        uint256 donationDai = DEFAULT_AMOUNT / 10;
        uint256 donationUsdc = DEFAULT_AMOUNT / 10;
        uint256 daiSwapAmountIn = _MIN_TRADE_AMOUNT - 1;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (uint256[] memory donationAmounts, , , uint256[] memory transferAmountHints) = _getDonationAndFees(
            donationDai,
            donationUsdc,
            0,
            protocolFeePercentage
        );

        // Should revert since the swap amount is below min.
        vm.expectRevert(IVaultErrors.TradeAmountTooSmall.selector);
        vm.prank(alice);
        cowRouter.swapExactInAndDonateSurplus(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            0,
            type(uint32).max,
            donationAmounts,
            transferAmountHints,
            bytes("")
        );
    }

    function testSwapExactInAndDonateSurplusTransferAmountHintSurplus() public {
        // 1% protocol fee percentage.
        uint256 protocolFeePercentage = 1e16;
        uint256 donationDai = DEFAULT_AMOUNT / 10;
        uint256 donationUsdc = DEFAULT_AMOUNT / 10;
        uint256 daiSwapAmountIn = DEFAULT_AMOUNT / 10;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        // Giving more DAI tokens will make the router to return the tokens to the sender.
        (
            uint256[] memory donationAmounts,
            uint256[] memory expectedProtocolFees,
            uint256[] memory donationAfterFees,
            uint256[] memory transferAmountHints
        ) = _getDonationAndFees(donationDai, donationUsdc, 2 * daiSwapAmountIn, protocolFeePercentage);

        uint256 expectedSwapAmountOut = _calculateAmountOutSwapExactIn(daiSwapAmountIn);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        vm.startPrank(alice);
        dai.transfer(address(vault), transferAmountHints[daiIdx]);
        usdc.transfer(address(vault), transferAmountHints[usdcIdx]);

        vm.expectEmit();
        emit ICowRouter.CoWSwapAndDonation(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            expectedSwapAmountOut,
            donationAfterFees,
            expectedProtocolFees,
            bytes("")
        );
        cowRouter.swapExactInAndDonateSurplus(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            0,
            type(uint32).max,
            donationAmounts,
            transferAmountHints,
            bytes("")
        );
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(cowRouter));

        // The extra tokens should return to the sender.
        _checkBalancesAfterSwapAndDonation(
            balancesBefore,
            balancesAfter,
            expectedProtocolFees,
            donationAmounts,
            daiSwapAmountIn,
            expectedSwapAmountOut,
            0
        );
    }

    function testSwapExactInAndDonateHintBiggerThanTransfer() public {
        // 1% protocol fee percentage.
        uint256 protocolFeePercentage = 1e16;
        uint256 donationDai = DEFAULT_AMOUNT / 10;
        uint256 donationUsdc = DEFAULT_AMOUNT / 10;
        uint256 daiSwapAmountIn = DEFAULT_AMOUNT / 10;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        uint256 expectedSwapAmountOut = _calculateAmountOutSwapExactIn(daiSwapAmountIn);

        // The hint is bigger than the transfer amount (2 * expectedSwapAmountIn).
        (uint256[] memory donationAmounts, , , uint256[] memory transferAmountHints) = _getDonationAndFees(
            donationDai,
            donationUsdc,
            2 * daiSwapAmountIn,
            protocolFeePercentage
        );

        vm.startPrank(alice);
        // Transfer the expected amount of DAI.
        dai.transfer(address(vault), daiSwapAmountIn);
        usdc.transfer(address(vault), transferAmountHints[usdcIdx]);

        vm.expectRevert(IVaultErrors.BalanceNotSettled.selector);
        cowRouter.swapExactInAndDonateSurplus(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            expectedSwapAmountOut,
            type(uint32).max,
            donationAmounts,
            transferAmountHints,
            bytes("")
        );
        vm.stopPrank();
    }

    function testSwapExactInAndDonateSurplusMissingToken() public {
        // 1% protocol fee percentage.
        uint256 protocolFeePercentage = 1e16;
        uint256 donationDai = DEFAULT_AMOUNT / 10;
        uint256 donationUsdc = DEFAULT_AMOUNT / 10;
        uint256 daiSwapAmountIn = DEFAULT_AMOUNT / 10;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        // Giving less dai tokens as hint will cause operation to revert.
        (uint256[] memory donationAmounts, , , uint256[] memory transferAmountHints) = _getDonationAndFees(
            donationDai,
            donationUsdc,
            daiSwapAmountIn - 1,
            protocolFeePercentage
        );

        vm.startPrank(alice);
        dai.transfer(address(vault), transferAmountHints[daiIdx]);
        usdc.transfer(address(vault), transferAmountHints[usdcIdx]);

        // Since there's not enough funds to pay the operation, it'll revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                ICowRouter.InsufficientFunds.selector,
                dai,
                transferAmountHints[daiIdx],
                donationDai + daiSwapAmountIn
            )
        );
        cowRouter.swapExactInAndDonateSurplus(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            0,
            type(uint32).max,
            donationAmounts,
            transferAmountHints,
            bytes("")
        );
        vm.stopPrank();
    }

    function testSwapExactInAndDonateSurplus__Fuzz(
        uint256 donationDai,
        uint256 donationUsdc,
        uint256 daiSwapAmountIn,
        uint256 protocolFeePercentage
    ) public {
        // ProtocolFeePercentage between 0 and MAX PROTOCOL FEE PERCENTAGE.
        protocolFeePercentage = bound(protocolFeePercentage, 0, cowRouter.getMaxProtocolFeePercentage());
        donationDai = _boundDonation(donationDai, protocolFeePercentage);
        donationUsdc = _boundDonation(donationUsdc, protocolFeePercentage);
        // A weighted swap cannot pass 30% of pool liquidity. Also, since the amount out cannot be lower than
        // _MIN_TRADE_AMOUNT, we set amount in to be at least 2x _MIN_TRADE_AMOUNT.
        daiSwapAmountIn = bound(daiSwapAmountIn, 2 * _MIN_TRADE_AMOUNT, DEFAULT_AMOUNT.mulDown(30e16));

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (
            uint256[] memory donationAmounts,
            uint256[] memory expectedProtocolFees,
            uint256[] memory donationAfterFees,
            uint256[] memory transferAmountHints
        ) = _getDonationAndFees(donationDai, donationUsdc, daiSwapAmountIn, protocolFeePercentage);

        uint256 expectedSwapAmountOut = _calculateAmountOutSwapExactIn(daiSwapAmountIn);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        vm.startPrank(alice);
        dai.transfer(address(vault), transferAmountHints[daiIdx]);
        usdc.transfer(address(vault), transferAmountHints[usdcIdx]);

        vm.expectEmit();
        emit ICowRouter.CoWSwapAndDonation(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            expectedSwapAmountOut,
            donationAfterFees,
            expectedProtocolFees,
            bytes("")
        );
        cowRouter.swapExactInAndDonateSurplus(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            0,
            type(uint32).max,
            donationAmounts,
            transferAmountHints,
            bytes("")
        );
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(cowRouter));

        _checkBalancesAfterSwapAndDonation(
            balancesBefore,
            balancesAfter,
            expectedProtocolFees,
            donationAmounts,
            daiSwapAmountIn,
            expectedSwapAmountOut,
            0
        );
    }

    /********************************************************
                  swapExactOutAndDonateSurplus()
    ********************************************************/

    function testSwapExactOutAndDonateSurplusIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        cowRouter.swapExactOutAndDonateSurplus(
            pool,
            dai,
            usdc,
            1e18,
            0,
            type(uint32).max,
            new uint256[](2),
            new uint256[](2),
            bytes("")
        );
    }

    function testSwapExactOutAndDonateSurplusLimit() public {
        // 1% protocol fee percentage.
        uint256 protocolFeePercentage = 1e16;
        uint256 donationDai = DEFAULT_AMOUNT / 10;
        uint256 donationUsdc = DEFAULT_AMOUNT / 10;
        uint256 usdcSwapAmountOut = DEFAULT_AMOUNT / 10;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (uint256[] memory donationAmounts, , , uint256[] memory transferAmountHints) = _getDonationAndFees(
            donationDai,
            donationUsdc,
            0,
            protocolFeePercentage
        );

        uint256 daiSwapAmountIn = _calculateAmountInSwapExactOut(usdcSwapAmountOut);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, daiSwapAmountIn, daiSwapAmountIn - 1));
        vm.prank(alice);
        cowRouter.swapExactOutAndDonateSurplus(
            pool,
            dai,
            usdc,
            daiSwapAmountIn - 1,
            usdcSwapAmountOut,
            type(uint32).max,
            donationAmounts,
            transferAmountHints,
            bytes("")
        );
    }

    function testSwapExactOutAndDonateSurplusDeadline() public {
        // 1% protocol fee percentage.
        uint256 protocolFeePercentage = 1e16;
        uint256 donationDai = DEFAULT_AMOUNT / 10;
        uint256 donationUsdc = DEFAULT_AMOUNT / 10;
        uint256 usdcSwapAmountOut = DEFAULT_AMOUNT / 10;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (uint256[] memory donationAmounts, , , uint256[] memory transferAmountHints) = _getDonationAndFees(
            donationDai,
            donationUsdc,
            0,
            protocolFeePercentage
        );

        vm.expectRevert(ICowRouter.SwapDeadline.selector);
        vm.prank(alice);
        // Since the blocknumber is bigger than the deadline, it should revert.
        uint256 deadline = block.number + 100;
        vm.warp(deadline + 1);
        cowRouter.swapExactOutAndDonateSurplus(
            pool,
            dai,
            usdc,
            MAX_UINT128,
            usdcSwapAmountOut,
            deadline,
            donationAmounts,
            transferAmountHints,
            bytes("")
        );
    }

    function testSwapExactOutAndDonateSurplusEmptyDonation() public {
        // 1% protocol fee percentage.
        uint256 protocolFeePercentage = 1e16;
        uint256 donationDai = 0;
        uint256 donationUsdc = 0;
        uint256 usdcSwapAmountOut = DEFAULT_AMOUNT / 10;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        uint256 daiSwapAmountIn = _calculateAmountInSwapExactOut(usdcSwapAmountOut);

        (
            uint256[] memory donationAmounts,
            uint256[] memory expectedProtocolFees,
            uint256[] memory donationAfterFees,
            uint256[] memory transferAmountHints
        ) = _getDonationAndFees(donationDai, donationUsdc, daiSwapAmountIn, protocolFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        // Should not revert, since there's no minimum limit in the donation.
        vm.startPrank(alice);
        dai.transfer(address(vault), transferAmountHints[daiIdx]);
        // Does not transfer USDC, since donation is 0 and the swap only requires DAI.

        vm.expectEmit();
        emit ICowRouter.CoWSwapAndDonation(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            usdcSwapAmountOut,
            donationAfterFees,
            expectedProtocolFees,
            bytes("")
        );
        cowRouter.swapExactOutAndDonateSurplus(
            pool,
            dai,
            usdc,
            MAX_UINT128,
            usdcSwapAmountOut,
            type(uint32).max,
            donationAmounts,
            transferAmountHints,
            bytes("")
        );
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(cowRouter));

        _checkBalancesAfterSwapAndDonation(
            balancesBefore,
            balancesAfter,
            expectedProtocolFees,
            donationAmounts,
            daiSwapAmountIn,
            usdcSwapAmountOut,
            0
        );
    }

    function testSwapExactOutAndDonateSurplusEmptySwap() public {
        // 1% protocol fee percentage.
        uint256 protocolFeePercentage = 1e16;
        uint256 donationDai = DEFAULT_AMOUNT / 10;
        uint256 donationUsdc = DEFAULT_AMOUNT / 10;
        uint256 usdcSwapAmountOut = 0;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (uint256[] memory donationAmounts, , , uint256[] memory transferAmountHints) = _getDonationAndFees(
            donationDai,
            donationUsdc,
            0,
            protocolFeePercentage
        );

        // Should revert, since swap amount cannot be zero.
        vm.expectRevert(IVaultErrors.AmountGivenZero.selector);
        vm.prank(alice);
        cowRouter.swapExactOutAndDonateSurplus(
            pool,
            dai,
            usdc,
            MAX_UINT128,
            usdcSwapAmountOut,
            type(uint32).max,
            donationAmounts,
            transferAmountHints,
            bytes("")
        );
    }

    function testSwapExactOutAndDonateSurplusBelowMinSwap() public {
        // 1% protocol fee percentage.
        uint256 protocolFeePercentage = 1e16;
        uint256 donationDai = DEFAULT_AMOUNT / 10;
        uint256 donationUsdc = DEFAULT_AMOUNT / 10;
        uint256 usdcSwapAmountOut = _MIN_TRADE_AMOUNT - 1;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (uint256[] memory donationAmounts, , , uint256[] memory transferAmountHints) = _getDonationAndFees(
            donationDai,
            donationUsdc,
            0,
            protocolFeePercentage
        );

        // Should revert since the swap amount is below min.
        vm.expectRevert(IVaultErrors.TradeAmountTooSmall.selector);
        vm.prank(alice);
        cowRouter.swapExactOutAndDonateSurplus(
            pool,
            dai,
            usdc,
            MAX_UINT128,
            usdcSwapAmountOut,
            type(uint32).max,
            donationAmounts,
            transferAmountHints,
            bytes("")
        );
    }

    function testSwapExactOutAndDonateTransferAmountHintSurplus() public {
        // 1% protocol fee percentage.
        uint256 protocolFeePercentage = 1e16;
        uint256 donationDai = DEFAULT_AMOUNT / 10;
        uint256 donationUsdc = DEFAULT_AMOUNT / 10;
        uint256 usdcSwapAmountOut = DEFAULT_AMOUNT / 10;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (
            uint256[] memory donationAmounts,
            uint256[] memory expectedProtocolFees,
            uint256[] memory donationAfterFees,
            uint256[] memory transferAmountHints
        ) = _getDonationAndFees(donationDai, donationUsdc, 2 * usdcSwapAmountOut, protocolFeePercentage);

        uint256 expectedSwapAmountIn = _calculateAmountInSwapExactOut(usdcSwapAmountOut);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        vm.startPrank(alice);
        dai.transfer(address(vault), transferAmountHints[daiIdx]);
        usdc.transfer(address(vault), transferAmountHints[usdcIdx]);

        vm.expectEmit();
        emit ICowRouter.CoWSwapAndDonation(
            pool,
            dai,
            usdc,
            expectedSwapAmountIn,
            usdcSwapAmountOut,
            donationAfterFees,
            expectedProtocolFees,
            bytes("")
        );
        cowRouter.swapExactOutAndDonateSurplus(
            pool,
            dai,
            usdc,
            MAX_UINT128,
            usdcSwapAmountOut,
            type(uint32).max,
            donationAmounts,
            transferAmountHints,
            bytes("")
        );
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(cowRouter));

        // The extra tokens should return to the sender.
        _checkBalancesAfterSwapAndDonation(
            balancesBefore,
            balancesAfter,
            expectedProtocolFees,
            donationAmounts,
            expectedSwapAmountIn,
            usdcSwapAmountOut,
            0
        );
    }

    function testSwapExactOutAndDonateHintBiggerThanTransfer() public {
        // 1% protocol fee percentage.
        uint256 protocolFeePercentage = 1e16;
        uint256 donationDai = DEFAULT_AMOUNT / 10;
        uint256 donationUsdc = DEFAULT_AMOUNT / 10;
        uint256 usdcSwapAmountOut = DEFAULT_AMOUNT / 10;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        uint256 expectedSwapAmountIn = _calculateAmountInSwapExactOut(usdcSwapAmountOut);

        // The hint is bigger than the transfer amount (2 * expectedSwapAmountIn).
        (uint256[] memory donationAmounts, , , uint256[] memory transferAmountHints) = _getDonationAndFees(
            donationDai,
            donationUsdc,
            2 * expectedSwapAmountIn,
            protocolFeePercentage
        );

        vm.startPrank(alice);
        // Transfer the expected amount of DAI.
        dai.transfer(address(vault), expectedSwapAmountIn);
        usdc.transfer(address(vault), transferAmountHints[usdcIdx]);

        vm.expectRevert(IVaultErrors.BalanceNotSettled.selector);
        cowRouter.swapExactOutAndDonateSurplus(
            pool,
            dai,
            usdc,
            MAX_UINT128,
            usdcSwapAmountOut,
            type(uint32).max,
            donationAmounts,
            transferAmountHints,
            bytes("")
        );
        vm.stopPrank();
    }

    function testSwapExactOutAndDonateSurplusMissingToken() public {
        // 1% protocol fee percentage.
        uint256 protocolFeePercentage = 1e16;
        uint256 donationDai = DEFAULT_AMOUNT / 10;
        uint256 donationUsdc = DEFAULT_AMOUNT / 10;
        uint256 usdcSwapAmountOut = DEFAULT_AMOUNT / 10;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        uint256 daiSwapAmountIn = _calculateAmountInSwapExactOut(usdcSwapAmountOut);

        // Giving less dai tokens as hint will cause operation to revert.
        (uint256[] memory donationAmounts, , , uint256[] memory transferAmountHints) = _getDonationAndFees(
            donationDai,
            donationUsdc,
            daiSwapAmountIn - 1,
            protocolFeePercentage
        );

        vm.startPrank(alice);
        dai.transfer(address(vault), transferAmountHints[daiIdx]);
        usdc.transfer(address(vault), transferAmountHints[usdcIdx]);

        // Since there's not enough funds to pay the operation, it'll revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                ICowRouter.InsufficientFunds.selector,
                dai,
                transferAmountHints[daiIdx],
                donationDai + daiSwapAmountIn // Since the pool is linear, amount in == amount out
            )
        );
        cowRouter.swapExactOutAndDonateSurplus(
            pool,
            dai,
            usdc,
            MAX_UINT128,
            usdcSwapAmountOut,
            type(uint32).max,
            donationAmounts,
            transferAmountHints,
            bytes("")
        );
        vm.stopPrank();
    }

    function testSwapExactOutAndDonateSurplus__Fuzz(
        uint256 donationDai,
        uint256 donationUsdc,
        uint256 usdcSwapAmountOut,
        uint256 protocolFeePercentage
    ) public {
        // ProtocolFeePercentage between 0 and MAX PROTOCOL FEE PERCENTAGE.
        protocolFeePercentage = bound(protocolFeePercentage, 0, cowRouter.getMaxProtocolFeePercentage());
        donationDai = _boundDonation(donationDai, protocolFeePercentage);
        donationUsdc = _boundDonation(donationUsdc, protocolFeePercentage);
        // A weighted swap cannot pass 30% of pool liquidity. Using 25% of pool liquidity to give some margin in the
        // calculation of amount in.
        usdcSwapAmountOut = bound(usdcSwapAmountOut, _MIN_TRADE_AMOUNT, DEFAULT_AMOUNT.mulDown(25e16));

        uint256 daiSwapAmountIn = _calculateAmountInSwapExactOut(usdcSwapAmountOut);

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (
            uint256[] memory donationAmounts,
            uint256[] memory expectedProtocolFees,
            uint256[] memory donationAfterFees,
            uint256[] memory transferAmountHints
        ) = _getDonationAndFees(donationDai, donationUsdc, daiSwapAmountIn, protocolFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        vm.startPrank(alice);
        dai.transfer(address(vault), transferAmountHints[daiIdx]);
        usdc.transfer(address(vault), transferAmountHints[usdcIdx]);

        vm.expectEmit();
        emit ICowRouter.CoWSwapAndDonation(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            usdcSwapAmountOut,
            donationAfterFees,
            expectedProtocolFees,
            bytes("")
        );
        cowRouter.swapExactOutAndDonateSurplus(
            pool,
            dai,
            usdc,
            MAX_UINT128,
            usdcSwapAmountOut,
            type(uint32).max,
            donationAmounts,
            transferAmountHints,
            bytes("")
        );
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(cowRouter));

        _checkBalancesAfterSwapAndDonation(
            balancesBefore,
            balancesAfter,
            expectedProtocolFees,
            donationAmounts,
            daiSwapAmountIn,
            usdcSwapAmountOut,
            0
        );
    }

    /********************************************************
                            donate()
    ********************************************************/

    function testDonateIsPermissioned() public {
        uint256[] memory donationAmounts = [DEFAULT_AMOUNT / 10, DEFAULT_AMOUNT / 10].toMemoryArray();

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        cowRouter.donate(pool, donationAmounts, bytes(""));
    }

    function testDonateTransferAmountHintSurplus(
        uint256 donationDai,
        uint256 donationUsdc,
        uint256 protocolFeePercentage
    ) public {
        // 1% Protocol Fee Percentage.
        protocolFeePercentage = 1e16;
        donationDai = DEFAULT_AMOUNT / 10;
        donationUsdc = DEFAULT_AMOUNT / 10;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (
            uint256[] memory donationAmounts,
            uint256[] memory expectedProtocolFees,
            uint256[] memory donationAfterFees,
            uint256[] memory transferAmountHints
        ) = _getDonationAndFees(donationDai, donationUsdc, 0, protocolFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        uint256 incorrectlySettledDaiTokens = transferAmountHints[daiIdx];

        vm.startPrank(alice);
        // In the case of a donation, any incorrect surplus in the transferAmountHints are locked in the vault. It
        // happens because the donate() function does not receive a hint and assumes the donation amounts were
        // correctly transferred by the sender (since they're exact amounts).
        dai.transfer(address(vault), transferAmountHints[daiIdx] + incorrectlySettledDaiTokens);
        usdc.transfer(address(vault), transferAmountHints[usdcIdx]);

        vm.expectEmit();
        emit ICowRouter.CoWDonation(pool, donationAfterFees, expectedProtocolFees, bytes(""));
        cowRouter.donate(pool, donationAmounts, bytes(""));
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(cowRouter));

        // The sender lost the excess of tokens sent to the Vault during the settle operation.
        _checkBalancesAfterSwapAndDonation(
            balancesBefore,
            balancesAfter,
            expectedProtocolFees,
            donationAmounts,
            0,
            0,
            incorrectlySettledDaiTokens
        );
    }

    function testDonateMissingToken(uint256 donationDai, uint256 donationUsdc, uint256 protocolFeePercentage) public {
        // 1% Protocol Fee Percentage.
        protocolFeePercentage = 1e16;
        donationDai = DEFAULT_AMOUNT / 10;
        donationUsdc = DEFAULT_AMOUNT / 10;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (uint256[] memory donationAmounts, , , uint256[] memory transferAmountHints) = _getDonationAndFees(
            donationDai,
            donationUsdc,
            0,
            protocolFeePercentage
        );

        uint256 daiMissing = 1;

        vm.startPrank(alice);
        dai.transfer(address(vault), transferAmountHints[daiIdx] - daiMissing);
        usdc.transfer(address(vault), transferAmountHints[usdcIdx]);

        // The operation should revert, since the user did not transfer the amount of tokens required to settle.
        vm.expectRevert(IVaultErrors.BalanceNotSettled.selector);
        cowRouter.donate(pool, donationAmounts, bytes(""));
        vm.stopPrank();
    }

    function testDonate__Fuzz(uint256 donationDai, uint256 donationUsdc, uint256 protocolFeePercentage) public {
        // ProtocolFeePercentage between 0 and MAX PROTOCOL FEE PERCENTAGE.
        protocolFeePercentage = bound(protocolFeePercentage, 0, cowRouter.getMaxProtocolFeePercentage());
        donationDai = _boundDonation(donationDai, protocolFeePercentage);
        donationUsdc = _boundDonation(donationUsdc, protocolFeePercentage);

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (
            uint256[] memory donationAmounts,
            uint256[] memory expectedProtocolFees,
            uint256[] memory donationAfterFees,
            uint256[] memory transferAmountHints
        ) = _getDonationAndFees(donationDai, donationUsdc, 0, protocolFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        vm.startPrank(alice);
        dai.transfer(address(vault), transferAmountHints[daiIdx]);
        usdc.transfer(address(vault), transferAmountHints[usdcIdx]);

        vm.expectEmit();
        emit ICowRouter.CoWDonation(pool, donationAfterFees, expectedProtocolFees, bytes(""));
        cowRouter.donate(pool, donationAmounts, bytes(""));
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(cowRouter));

        _checkBalancesAfterSwapAndDonation(
            balancesBefore,
            balancesAfter,
            expectedProtocolFees,
            donationAmounts,
            0,
            0,
            0
        );
    }

    /********************************************************
                       ProtocolFeePercentage
    ********************************************************/

    function testGetProtocolFeePercentage() public {
        assertEq(
            cowRouter.getProtocolFeePercentage(),
            _INITIAL_PROTOCOL_FEE_PERCENTAGE,
            "Wrong protocol fee percentage"
        );

        uint256 newProtocolFeePercentage = 5e16;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(newProtocolFeePercentage);

        assertEq(cowRouter.getProtocolFeePercentage(), newProtocolFeePercentage, "Protocol fee percentage was not set");
    }

    function testSetProtocolFeePercentageIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        cowRouter.setProtocolFeePercentage(50e16);
    }

    function testSetProtocolFeePercentageCappedAtMax() public {
        // Any value above the MAX_PROTOCOL_FEE_PERCENTAGE should revert.
        uint256 newProtocolFeePercentage = cowRouter.getMaxProtocolFeePercentage() + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ICowRouter.ProtocolFeePercentageAboveLimit.selector,
                newProtocolFeePercentage,
                cowRouter.getMaxProtocolFeePercentage()
            )
        );
        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(newProtocolFeePercentage);
    }

    function testSetProtocolFeePercentage() public {
        // 5% protocol fee percentage.
        uint256 newProtocolFeePercentage = 5e16;

        vm.prank(admin);
        vm.expectEmit();
        emit ICowRouter.ProtocolFeePercentageChanged(newProtocolFeePercentage);
        cowRouter.setProtocolFeePercentage(newProtocolFeePercentage);

        assertEq(cowRouter.getProtocolFeePercentage(), newProtocolFeePercentage, "Protocol Fee Percentage is not set");
    }

    /********************************************************
                          Fee Sweeper
    ********************************************************/
    function testGetFeeSweeper() public {
        assertEq(cowRouter.getFeeSweeper(), feeSweeper, "Wrong fee sweeper");

        address newFeeSweeper = address(1);

        vm.prank(admin);
        cowRouter.setFeeSweeper(newFeeSweeper);

        assertEq(cowRouter.getFeeSweeper(), newFeeSweeper, "Fee sweeper was not set properly");
    }

    function testSetFeeSweeperIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        cowRouter.setFeeSweeper(address(1));
    }

    function testSetFeeSweeperInvalidAddress() public {
        // Address 0 is not a valid fee sweeper.
        vm.expectRevert(abi.encodeWithSelector(ICowRouter.InvalidFeeSweeper.selector));
        vm.prank(admin);
        cowRouter.setFeeSweeper(address(0));
    }

    function testSetFeeSweeper() public {
        address newFeeSweeper = address(2);

        vm.prank(admin);
        vm.expectEmit();
        emit ICowRouter.FeeSweeperChanged(newFeeSweeper);
        cowRouter.setFeeSweeper(newFeeSweeper);

        assertEq(cowRouter.getFeeSweeper(), newFeeSweeper, "Fee sweeper was set properly");
    }

    function testWithdrawCollectedProtocolFees() public {
        uint256 protocolFeePercentage = _INITIAL_PROTOCOL_FEE_PERCENTAGE;
        uint256 donationDai = DEFAULT_AMOUNT / 10;
        uint256 donationUsdc = DEFAULT_AMOUNT / 10;

        (uint256[] memory donationAmounts, , , ) = _getDonationAndFees(
            donationDai,
            donationUsdc,
            0,
            protocolFeePercentage
        );

        vm.startPrank(alice);
        dai.transfer(address(vault), donationAmounts[daiIdx]);
        usdc.transfer(address(vault), donationAmounts[usdcIdx]);

        cowRouter.donate(pool, donationAmounts, bytes(""));
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        uint256 daiProtocolFeesBeforeWithdraw = cowRouter.getCollectedProtocolFees(dai);
        uint256 usdcProtocolFeesBeforeWithdraw = cowRouter.getCollectedProtocolFees(usdc);

        assertEq(
            balancesBefore.userTokens[daiIdx],
            daiProtocolFeesBeforeWithdraw,
            "CoW Router has a wrong amount of DAI to withdraw"
        );
        assertEq(
            balancesBefore.userTokens[usdcIdx],
            usdcProtocolFeesBeforeWithdraw,
            "CoW Router has a wrong amount of USDC to withdraw"
        );

        vm.expectEmit();
        emit ICowRouter.ProtocolFeesWithdrawn(dai, bob, daiProtocolFeesBeforeWithdraw);
        cowRouter.withdrawCollectedProtocolFees(dai);

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(cowRouter));

        assertEq(balancesAfter.userTokens[daiIdx], 0, "CoW Router has DAI tokens to withdraw");
        assertEq(cowRouter.getCollectedProtocolFees(dai), 0, "CoW Router state of protocol fees for DAI is not 0");
        // Bob is the current feeSweeper, as set by BaseCowTest contract.
        assertEq(
            balancesAfter.bobTokens[daiIdx],
            balancesBefore.bobTokens[daiIdx] + daiProtocolFeesBeforeWithdraw,
            "DAI tokens were not transferred to the fee sweeper"
        );

        // Change fee sweeper to Alice and check if the new fee sweeper receives the protocol fees.
        vm.prank(admin);
        cowRouter.setFeeSweeper(alice);

        vm.expectEmit();
        emit ICowRouter.ProtocolFeesWithdrawn(usdc, alice, usdcProtocolFeesBeforeWithdraw);
        cowRouter.withdrawCollectedProtocolFees(usdc);

        BaseVaultTest.Balances memory balancesAfterUsdc = getBalances(address(cowRouter));

        assertEq(balancesAfterUsdc.userTokens[usdcIdx], 0, "CoW Router has USDC tokens to withdraw");
        assertEq(cowRouter.getCollectedProtocolFees(usdc), 0, "CoW Router state of protocol fees for USDC is not 0");
        // Alice now is the current feeSweeper.
        assertEq(
            balancesAfterUsdc.aliceTokens[usdcIdx],
            balancesBefore.aliceTokens[usdcIdx] + usdcProtocolFeesBeforeWithdraw,
            "USDC tokens were not transferred to the fee sweeper"
        );
    }

    /********************************************************
                          Private Helpers
    ********************************************************/

    function _getDonationAndFees(
        uint256 donationDai,
        uint256 donationUsdc,
        uint256 swapDaiExactIn,
        uint256 protocolFeePercentage
    )
        private
        view
        returns (
            uint256[] memory donationAmounts,
            uint256[] memory expectedProtocolFees,
            uint256[] memory donationAfterFees,
            uint256[] memory transferAmountHints
        )
    {
        donationAmounts = new uint256[](2);
        donationAmounts[daiIdx] = donationDai;
        donationAmounts[usdcIdx] = donationUsdc;

        expectedProtocolFees = new uint256[](2);
        expectedProtocolFees[daiIdx] = donationDai.mulUp(protocolFeePercentage);
        expectedProtocolFees[usdcIdx] = donationUsdc.mulUp(protocolFeePercentage);

        donationAfterFees = new uint256[](2);
        donationAfterFees[daiIdx] = donationDai - expectedProtocolFees[daiIdx];
        donationAfterFees[usdcIdx] = donationUsdc - expectedProtocolFees[usdcIdx];

        transferAmountHints = new uint256[](2);
        transferAmountHints[daiIdx] = donationDai + swapDaiExactIn;
        transferAmountHints[usdcIdx] = donationUsdc;
    }

    function _checkBalancesAfterSwapAndDonation(
        BaseVaultTest.Balances memory balancesBefore,
        BaseVaultTest.Balances memory balancesAfter,
        uint256[] memory expectedProtocolFees,
        uint256[] memory donations,
        uint256 daiSwapAmountIn,
        uint256 usdcSwapAmountOut,
        uint256 incorrectlySettledDaiTokens
    ) private view {
        // Test collected protocol fee (router balance and state). Notice that userTokens refer to CoWRouter tokens,
        // since CoWRouter address was passed as the input of getBalances() function.
        assertEq(
            balancesAfter.userTokens[daiIdx],
            balancesBefore.userTokens[daiIdx] + expectedProtocolFees[daiIdx],
            "Router did not collect DAI protocol fees"
        );
        assertEq(
            cowRouter.getCollectedProtocolFees(dai),
            expectedProtocolFees[daiIdx],
            "Collected DAI fees not registered in the router state"
        );

        assertEq(
            balancesAfter.userTokens[usdcIdx],
            balancesBefore.userTokens[usdcIdx] + expectedProtocolFees[usdcIdx],
            "Router did not collect USDC protocol fees"
        );
        assertEq(
            cowRouter.getCollectedProtocolFees(usdc),
            expectedProtocolFees[usdcIdx],
            "Collected USDC fees not registered in the router state"
        );

        // Test BPT did not change
        assertEq(balancesAfter.aliceBpt, balancesBefore.aliceBpt, "Alice BPT has changed");
        assertEq(balancesAfter.poolSupply, balancesBefore.poolSupply, "BPT supply has changed");

        // Test new pool balances
        assertEq(
            balancesAfter.poolTokens[daiIdx],
            balancesBefore.poolTokens[daiIdx] + donations[daiIdx] - expectedProtocolFees[daiIdx] + daiSwapAmountIn,
            "Pool DAI balance is not correct"
        );
        assertEq(
            balancesAfter.poolTokens[usdcIdx],
            balancesBefore.poolTokens[usdcIdx] + donations[usdcIdx] - expectedProtocolFees[usdcIdx] - usdcSwapAmountOut,
            "Pool USDC balance is not correct"
        );

        // Test vault balances

        // Tokens going into the Vault:
        // - Donation
        // - Swap DAI exact in
        // - Incorrectly settled DAI tokens
        //
        // Tokens coming out of the Vault:
        // - Swap USDC exact out
        // - Protocol fees
        assertEq(
            balancesAfter.vaultTokens[daiIdx],
            balancesBefore.vaultTokens[daiIdx] +
                donations[daiIdx] +
                daiSwapAmountIn +
                incorrectlySettledDaiTokens -
                expectedProtocolFees[daiIdx],
            "Vault DAI balance is not correct"
        );
        assertEq(
            balancesAfter.vaultTokens[usdcIdx],
            balancesBefore.vaultTokens[usdcIdx] +
                donations[usdcIdx] -
                expectedProtocolFees[usdcIdx] -
                usdcSwapAmountOut,
            "Vault USDC balance is not correct"
        );

        // Test donor balances
        assertEq(
            balancesAfter.aliceTokens[daiIdx],
            balancesBefore.aliceTokens[daiIdx] - donations[daiIdx] - daiSwapAmountIn - incorrectlySettledDaiTokens,
            "Alice DAI balance is not correct"
        );
        assertEq(
            balancesAfter.aliceTokens[usdcIdx],
            balancesBefore.aliceTokens[usdcIdx] - donations[usdcIdx] + usdcSwapAmountOut,
            "Alice USDC balance is not correct"
        );
    }

    function _boundDonation(uint256 donation, uint256 protocolFeePercentage) private pure returns (uint256) {
        // The donation discounts the fee percentage before AddLiquidity is called. So, the minimum amount to donate
        // without reverting is `MinimumTradeAmount/(1 - fee%)`. This value comes from the formula
        // `MinimumTradeAmount = donation - Fees`, where fees is `fee% * donation`.
        return bound(donation, _MIN_TRADE_AMOUNT.divUp(FixedPoint.ONE - protocolFeePercentage), DEFAULT_AMOUNT);
    }

    function _calculateAmountOutSwapExactIn(uint256 daiSwapAmountIn) private returns (uint256 amountOut) {
        // The pool static fee percentage is independent from the protocol fee percentage charged on donations by the
        // CoW Router.
        uint256 staticSwapFeePercentage = vault.getStaticSwapFeePercentage(pool);

        vm.prank(address(vault));
        return
            IBasePool(pool).onSwap(
                PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: daiSwapAmountIn - daiSwapAmountIn.mulUp(staticSwapFeePercentage),
                    balancesScaled18: [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(cowRouter),
                    userData: bytes("")
                })
            );
    }

    function _calculateAmountInSwapExactOut(uint256 usdcSwapAmountOut) private returns (uint256) {
        // The pool static fee percentage is independent from the protocol fee percentage charged on donations by the
        // CoW Router.
        uint256 staticSwapFeePercentage = vault.getStaticSwapFeePercentage(pool);

        vm.prank(address(vault));
        uint256 amountInNoFees = IBasePool(pool).onSwap(
            PoolSwapParams({
                kind: SwapKind.EXACT_OUT,
                amountGivenScaled18: usdcSwapAmountOut,
                balancesScaled18: [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
                indexIn: daiIdx,
                indexOut: usdcIdx,
                router: address(cowRouter),
                userData: bytes("")
            })
        );

        return amountInNoFees + amountInNoFees.mulDivUp(staticSwapFeePercentage, staticSwapFeePercentage.complement());
    }
}
