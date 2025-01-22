// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { ICowRouter } from "@balancer-labs/v3-interfaces/contracts/pool-cow/ICowRouter.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { BaseCowTest } from "./utils/BaseCowTest.sol";
import { CowRouter } from "../../contracts/CowRouter.sol";

contract CowRouterTest is BaseCowTest {
    using FixedPoint for uint256;

    // 10% max protocol fee percentage.
    uint256 private constant _MAX_PROTOCOL_FEE_PERCENTAGE = 10e16;
    uint256 private constant _MIN_TRADE_AMOUNT = 1e6;

    function setUp() public override {
        vaultMockMinTradeAmount = _MIN_TRADE_AMOUNT;
        super.setUp();

        authorizer.grantRole(
            CowRouter(address(cowRouter)).getActionId(ICowRouter.swapExactInAndDonateSurplus.selector),
            lp
        );
        authorizer.grantRole(
            CowRouter(address(cowRouter)).getActionId(ICowRouter.swapExactOutAndDonateSurplus.selector),
            lp
        );
    }

    /********************************************************
                  swapExactInAndDonateSurplus()
    ********************************************************/
    function testSwapExactInAndDonateSurplusIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        cowRouter.swapExactInAndDonateSurplus(pool, dai, usdc, 1e18, 0, type(uint32).max, new uint256[](2), bytes(""));
    }

    function testSwapExactInAndDonateSurplusLimit() public {
        // 1% protocol fee percentage.
        uint256 protocolFeePercentage = 1e16;
        uint256 donationDai = DEFAULT_AMOUNT / 10;
        uint256 donationUsdc = DEFAULT_AMOUNT / 10;
        uint256 daiSwapAmountIn = DEFAULT_AMOUNT / 10;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (uint256[] memory donationAmounts, , ) = _getDonationAndFees(donationDai, donationUsdc, protocolFeePercentage);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, daiSwapAmountIn, daiSwapAmountIn + 1));
        vm.prank(lp);
        // Since the pool is linear, the expected amount out is `daiSwapAmountIn`. If the limit is bigger than that,
        // the swap should revert.
        cowRouter.swapExactInAndDonateSurplus(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            daiSwapAmountIn + 1,
            type(uint32).max,
            donationAmounts,
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

        (uint256[] memory donationAmounts, , ) = _getDonationAndFees(donationDai, donationUsdc, protocolFeePercentage);

        vm.expectRevert(ICowRouter.SwapDeadline.selector);
        vm.prank(lp);
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
            uint256[] memory donationAfterFees
        ) = _getDonationAndFees(donationDai, donationUsdc, protocolFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        vm.expectEmit();
        emit ICowRouter.CoWSwapAndDonation(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            daiSwapAmountIn, // PoolMock is linear, so amounts in == amounts out
            donationAfterFees,
            expectedProtocolFees,
            bytes("")
        );

        // Should not revert, since there's no minimum limit in the donation.
        vm.prank(lp);
        cowRouter.swapExactInAndDonateSurplus(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            0,
            type(uint32).max,
            donationAmounts,
            bytes("")
        );

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(cowRouter));

        // Since the pool is linear, amount in == amount out
        _checkBalancesAfterSwapAndDonation(
            balancesBefore,
            balancesAfter,
            expectedProtocolFees,
            donationAmounts,
            daiSwapAmountIn,
            daiSwapAmountIn
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

        (uint256[] memory donationAmounts, , ) = _getDonationAndFees(donationDai, donationUsdc, protocolFeePercentage);

        // Should revert, since swap amount cannot be zero.
        vm.expectRevert(IVaultErrors.AmountGivenZero.selector);
        vm.prank(lp);
        cowRouter.swapExactInAndDonateSurplus(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            0,
            type(uint32).max,
            donationAmounts,
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

        (uint256[] memory donationAmounts, , ) = _getDonationAndFees(donationDai, donationUsdc, protocolFeePercentage);

        // Should revert since the swap amount is below min.
        vm.expectRevert(IVaultErrors.TradeAmountTooSmall.selector);
        vm.prank(lp);
        cowRouter.swapExactInAndDonateSurplus(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            0,
            type(uint32).max,
            donationAmounts,
            bytes("")
        );
    }

    function testSwapExactInAndDonateSurplus__Fuzz(
        uint256 donationDai,
        uint256 donationUsdc,
        uint256 daiSwapAmountIn,
        uint256 protocolFeePercentage
    ) public {
        // ProtocolFeePercentage between 0 and MAX PROTOCOL FEE PERCENTAGE.
        protocolFeePercentage = bound(protocolFeePercentage, 0, _MAX_PROTOCOL_FEE_PERCENTAGE);
        donationDai = _boundDonation(donationDai, protocolFeePercentage);
        donationUsdc = _boundDonation(donationUsdc, protocolFeePercentage);
        daiSwapAmountIn = bound(daiSwapAmountIn, _MIN_TRADE_AMOUNT, DEFAULT_AMOUNT);

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (
            uint256[] memory donationAmounts,
            uint256[] memory expectedProtocolFees,
            uint256[] memory donationAfterFees
        ) = _getDonationAndFees(donationDai, donationUsdc, protocolFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        vm.expectEmit();
        emit ICowRouter.CoWSwapAndDonation(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            daiSwapAmountIn, // PoolMock is linear, so amounts in == amounts out
            donationAfterFees,
            expectedProtocolFees,
            bytes("")
        );

        vm.prank(lp);
        cowRouter.swapExactInAndDonateSurplus(
            pool,
            dai,
            usdc,
            daiSwapAmountIn,
            0,
            type(uint32).max,
            donationAmounts,
            bytes("")
        );

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(cowRouter));

        // Since the pool is linear, amount in == amount out
        _checkBalancesAfterSwapAndDonation(
            balancesBefore,
            balancesAfter,
            expectedProtocolFees,
            donationAmounts,
            daiSwapAmountIn,
            daiSwapAmountIn
        );
    }

    /********************************************************
                  swapExactOutAndDonateSurplus()
    ********************************************************/
    function testSwapExactOutAndDonateSurplusIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        cowRouter.swapExactOutAndDonateSurplus(pool, dai, usdc, 1e18, 0, type(uint32).max, new uint256[](2), bytes(""));
    }

    function testSwapExactOutAndDonateSurplusLimit() public {
        // 1% protocol fee percentage.
        uint256 protocolFeePercentage = 1e16;
        uint256 donationDai = DEFAULT_AMOUNT / 10;
        uint256 donationUsdc = DEFAULT_AMOUNT / 10;
        uint256 usdcSwapAmountOut = DEFAULT_AMOUNT / 10;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (uint256[] memory donationAmounts, , ) = _getDonationAndFees(donationDai, donationUsdc, protocolFeePercentage);

        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, usdcSwapAmountOut, usdcSwapAmountOut - 1)
        );
        vm.prank(lp);
        // Since the pool is linear, the expected amount in is `usdcSwapAmountOut`. If the limit is smaller than that,
        // the swap should revert.
        cowRouter.swapExactOutAndDonateSurplus(
            pool,
            dai,
            usdc,
            usdcSwapAmountOut - 1,
            usdcSwapAmountOut,
            type(uint32).max,
            donationAmounts,
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

        (uint256[] memory donationAmounts, , ) = _getDonationAndFees(donationDai, donationUsdc, protocolFeePercentage);

        vm.expectRevert(ICowRouter.SwapDeadline.selector);
        vm.prank(lp);
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

        (
            uint256[] memory donationAmounts,
            uint256[] memory expectedProtocolFees,
            uint256[] memory donationAfterFees
        ) = _getDonationAndFees(donationDai, donationUsdc, protocolFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        vm.expectEmit();
        emit ICowRouter.CoWSwapAndDonation(
            pool,
            dai,
            usdc,
            usdcSwapAmountOut, // PoolMock is linear, so amounts in == amounts out
            usdcSwapAmountOut,
            donationAfterFees,
            expectedProtocolFees,
            bytes("")
        );

        // Should not revert, since there's no minimum limit in the donation.
        vm.prank(lp);
        cowRouter.swapExactOutAndDonateSurplus(
            pool,
            dai,
            usdc,
            MAX_UINT128,
            usdcSwapAmountOut,
            type(uint32).max,
            donationAmounts,
            bytes("")
        );

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(cowRouter));

        // Since the pool is linear, amount in == amount out
        _checkBalancesAfterSwapAndDonation(
            balancesBefore,
            balancesAfter,
            expectedProtocolFees,
            donationAmounts,
            usdcSwapAmountOut,
            usdcSwapAmountOut
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

        (uint256[] memory donationAmounts, , ) = _getDonationAndFees(donationDai, donationUsdc, protocolFeePercentage);

        // Should revert, since swap amount cannot be zero.
        vm.expectRevert(IVaultErrors.AmountGivenZero.selector);
        vm.prank(lp);
        cowRouter.swapExactOutAndDonateSurplus(
            pool,
            dai,
            usdc,
            MAX_UINT128,
            usdcSwapAmountOut,
            type(uint32).max,
            donationAmounts,
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

        (uint256[] memory donationAmounts, , ) = _getDonationAndFees(donationDai, donationUsdc, protocolFeePercentage);

        // Should revert since the swap amount is below min.
        vm.expectRevert(IVaultErrors.TradeAmountTooSmall.selector);
        vm.prank(lp);
        cowRouter.swapExactOutAndDonateSurplus(
            pool,
            dai,
            usdc,
            MAX_UINT128,
            usdcSwapAmountOut,
            type(uint32).max,
            donationAmounts,
            bytes("")
        );
    }

    function testSwapExactOutAndDonateSurplus__Fuzz(
        uint256 donationDai,
        uint256 donationUsdc,
        uint256 usdcSwapAmountOut,
        uint256 protocolFeePercentage
    ) public {
        // ProtocolFeePercentage between 0 and MAX PROTOCOL FEE PERCENTAGE.
        protocolFeePercentage = bound(protocolFeePercentage, 0, _MAX_PROTOCOL_FEE_PERCENTAGE);
        donationDai = _boundDonation(donationDai, protocolFeePercentage);
        donationUsdc = _boundDonation(donationUsdc, protocolFeePercentage);
        usdcSwapAmountOut = bound(usdcSwapAmountOut, _MIN_TRADE_AMOUNT, DEFAULT_AMOUNT);

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (
            uint256[] memory donationAmounts,
            uint256[] memory expectedProtocolFees,
            uint256[] memory donationAfterFees
        ) = _getDonationAndFees(donationDai, donationUsdc, protocolFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        vm.expectEmit();
        emit ICowRouter.CoWSwapAndDonation(
            pool,
            dai,
            usdc,
            usdcSwapAmountOut, // PoolMock is linear, so amounts in == amounts out
            usdcSwapAmountOut,
            donationAfterFees,
            expectedProtocolFees,
            bytes("")
        );

        vm.prank(lp);
        cowRouter.swapExactOutAndDonateSurplus(
            pool,
            dai,
            usdc,
            MAX_UINT128,
            usdcSwapAmountOut,
            type(uint32).max,
            donationAmounts,
            bytes("")
        );

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(cowRouter));

        // Since the pool is linear, amount in == amount out
        _checkBalancesAfterSwapAndDonation(
            balancesBefore,
            balancesAfter,
            expectedProtocolFees,
            donationAmounts,
            usdcSwapAmountOut,
            usdcSwapAmountOut
        );
    }

    /********************************************************
                            donate()
    ********************************************************/
    function testDonate__Fuzz(uint256 donationDai, uint256 donationUsdc, uint256 protocolFeePercentage) public {
        // ProtocolFeePercentage between 0 and MAX PROTOCOL FEE PERCENTAGE.
        protocolFeePercentage = bound(protocolFeePercentage, 0, _MAX_PROTOCOL_FEE_PERCENTAGE);
        donationDai = _boundDonation(donationDai, protocolFeePercentage);
        donationUsdc = _boundDonation(donationUsdc, protocolFeePercentage);

        console.log("donationDai ", donationDai);
        console.log("donationUsdc", donationUsdc);

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (
            uint256[] memory donationAmounts,
            uint256[] memory expectedProtocolFees,
            uint256[] memory donationAfterFees
        ) = _getDonationAndFees(donationDai, donationUsdc, protocolFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        vm.expectEmit();
        emit ICowRouter.CoWDonation(pool, donationAfterFees, expectedProtocolFees, bytes(""));

        vm.prank(lp);
        cowRouter.donate(pool, donationAmounts, bytes(""));

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(cowRouter));

        _checkBalancesAfterSwapAndDonation(balancesBefore, balancesAfter, expectedProtocolFees, donationAmounts, 0, 0);
    }

    /********************************************************
                     getProtocolFeePercentage()
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

    /********************************************************
                     setProtocolFeePercentage()
    ********************************************************/
    function testSetProtocolFeePercentageIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        cowRouter.setProtocolFeePercentage(50e16);
    }

    function testSetProtocolFeePercentageCappedAtMax() public {
        // Any value above the MAX_PROTOCOL_FEE_PERCENTAGE should revert.
        uint256 newProtocolFeePercentage = _MAX_PROTOCOL_FEE_PERCENTAGE + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ICowRouter.ProtocolFeePercentageAboveLimit.selector,
                newProtocolFeePercentage,
                _MAX_PROTOCOL_FEE_PERCENTAGE
            )
        );
        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(newProtocolFeePercentage);
    }

    function testSetProtocolFeePercentage() public {
        // 5% protocol fee percentage.
        uint256 newProtocolFeePercentage = 5e16;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(newProtocolFeePercentage);

        assertEq(cowRouter.getProtocolFeePercentage(), newProtocolFeePercentage, "Protocol Fee Percentage is not set");
    }

    /********************************************************
                          Private Helpers
    ********************************************************/
    function _getDonationAndFees(
        uint256 donationDai,
        uint256 donationUsdc,
        uint256 protocolFeePercentage
    )
        private
        view
        returns (
            uint256[] memory donationAmounts,
            uint256[] memory expectedProtocolFees,
            uint256[] memory donationAfterFees
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
    }

    function _checkBalancesAfterSwapAndDonation(
        BaseVaultTest.Balances memory balancesBefore,
        BaseVaultTest.Balances memory balancesAfter,
        uint256[] memory expectedProtocolFees,
        uint256[] memory donations,
        uint256 daiSwapAmountIn,
        uint256 usdcSwapAmountOut
    ) private view {
        // Test collected protocol fee (router balance and state)
        assertEq(
            balancesAfter.userTokens[daiIdx],
            balancesBefore.userTokens[daiIdx] + expectedProtocolFees[daiIdx],
            "Router did not collect DAI protocol fees"
        );
        assertEq(
            cowRouter.getProtocolFees(dai),
            expectedProtocolFees[daiIdx],
            "Collected DAI fees not registered in the router state"
        );

        assertEq(
            balancesAfter.userTokens[usdcIdx],
            balancesBefore.userTokens[usdcIdx] + expectedProtocolFees[usdcIdx],
            "Router did not collect USDC protocol fees"
        );
        assertEq(
            cowRouter.getProtocolFees(usdc),
            expectedProtocolFees[usdcIdx],
            "Collected USDC fees not registered in the router state"
        );

        // Test BPT did not change
        assertEq(balancesAfter.lpBpt, balancesBefore.lpBpt, "LP BPT has changed");
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
        assertEq(
            balancesAfter.vaultTokens[daiIdx],
            balancesBefore.vaultTokens[daiIdx] + donations[daiIdx] - expectedProtocolFees[daiIdx] + daiSwapAmountIn,
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
            balancesAfter.lpTokens[daiIdx],
            balancesBefore.lpTokens[daiIdx] - donations[daiIdx] - daiSwapAmountIn,
            "LP DAI balance is not correct"
        );
        assertEq(
            balancesAfter.lpTokens[usdcIdx],
            balancesBefore.lpTokens[usdcIdx] - donations[usdcIdx] + usdcSwapAmountOut,
            "LP USDC balance is not correct"
        );
    }

    function _boundDonation(uint256 donation, uint256 protocolFeePercentage) private pure returns (uint256) {
        // The donation discounts the fee percentage before AddLiquidity is called. So, the minimum amount to donate
        // without reverting is `MinimumTradeAmount/(1 - fee%)`. This value comes from the formula
        // `MinimumTradeAmount = donation - Fees`, where fees is `fee% * donation`.
        return bound(donation, _MIN_TRADE_AMOUNT.divUp(FixedPoint.ONE - protocolFeePercentage), DEFAULT_AMOUNT);
    }
}
