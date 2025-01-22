// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { ICowRouter } from "@balancer-labs/v3-interfaces/contracts/pool-cow/ICowRouter.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { BaseCowTest } from "./utils/BaseCowTest.sol";
import { CowRouter } from "../../contracts/CowRouter.sol";

contract CowRouterTest is BaseCowTest {
    using FixedPoint for uint256;

    // 10% max protocol fee percentage.
    uint256 private constant _MAX_PROTOCOL_FEE_PERCENTAGE = 10e16;

    function setUp() public override {
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

    // TODO test limit
    // TODO test deadline
    // TODO test empty donation
    // TODO test empty swap
    // TODO test amount below min

    function testSwapExactInAndDonateSurplus__Fuzz(
        uint256 donationDai,
        uint256 donationUsdc,
        uint256 daiSwapAmountIn,
        uint256 protocolFeePercentage
    ) public {
        // ProtocolFeePercentage between 0 and MAX PROTOCOL FEE PERCENTAGE.
        protocolFeePercentage = bound(protocolFeePercentage, 0, _MAX_PROTOCOL_FEE_PERCENTAGE);
        donationDai = bound(donationDai, 1e6, DEFAULT_AMOUNT);
        donationUsdc = bound(donationUsdc, 1e6, DEFAULT_AMOUNT);
        daiSwapAmountIn = bound(daiSwapAmountIn, 1e6, DEFAULT_AMOUNT);

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (
            uint256[] memory donationAmounts,
            uint256[] memory expectedProtocolFees,
            uint256[] memory donationAfterFees
        ) = _getDonationAndFees(donationDai, donationUsdc, protocolFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        vm.expectEmit();
        emit ICowRouter.CoWSwapAndDonation(
            pool,
            daiSwapAmountIn,
            dai,
            daiSwapAmountIn, // PoolMock is linear, so amounts in == amounts out
            usdc,
            tokens,
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

    function testSwapExactOutAndDonateSurplus__Fuzz(
        uint256 donationDai,
        uint256 donationUsdc,
        uint256 usdcSwapAmountOut,
        uint256 protocolFeePercentage
    ) public {
        // ProtocolFeePercentage between 0 and MAX PROTOCOL FEE PERCENTAGE.
        protocolFeePercentage = bound(protocolFeePercentage, 0, _MAX_PROTOCOL_FEE_PERCENTAGE);
        donationDai = bound(donationDai, 1e6, DEFAULT_AMOUNT);
        donationUsdc = bound(donationUsdc, 1e6, DEFAULT_AMOUNT);
        usdcSwapAmountOut = bound(usdcSwapAmountOut, 1e6, DEFAULT_AMOUNT);

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (
            uint256[] memory donationAmounts,
            uint256[] memory expectedProtocolFees,
            uint256[] memory donationAfterFees
        ) = _getDonationAndFees(donationDai, donationUsdc, protocolFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        vm.expectEmit();
        emit ICowRouter.CoWSwapAndDonation(
            pool,
            usdcSwapAmountOut, // PoolMock is linear, so amounts in == amounts out
            dai,
            usdcSwapAmountOut,
            usdc,
            tokens,
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
        donationDai = bound(donationDai, 1e6, DEFAULT_AMOUNT);
        donationUsdc = bound(donationUsdc, 1e6, DEFAULT_AMOUNT);

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        (
            uint256[] memory donationAmounts,
            uint256[] memory expectedProtocolFees,
            uint256[] memory donationAfterFees
        ) = _getDonationAndFees(donationDai, donationUsdc, protocolFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        vm.expectEmit();
        emit ICowRouter.CoWDonation(pool, tokens, donationAfterFees, expectedProtocolFees, bytes(""));

        vm.prank(lp);
        cowRouter.donate(pool, donationAmounts, bytes(""));

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(cowRouter));

        _checkBalancesAfterSwapAndDonation(balancesBefore, balancesAfter, expectedProtocolFees, donationAmounts, 0, 0);
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
}
