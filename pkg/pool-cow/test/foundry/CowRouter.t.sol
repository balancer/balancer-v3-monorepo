// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { ICowRouter } from "@balancer-labs/v3-interfaces/contracts/pool-cow/ICowRouter.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { BaseCowTest } from "./utils/BaseCowTest.sol";
import { CowRouter } from "../../contracts/CowRouter.sol";

contract CowRouterTest is BaseCowTest {
    using FixedPoint for uint256;

    /********************************************************
                            donate()
    ********************************************************/
    function testDonate__Fuzz(uint256 amountDai, uint256 amountUsdc, uint256 protocolFeePercentage) public {
        // ProtocolFeePercentage between 0 and 10%.
        protocolFeePercentage = bound(protocolFeePercentage, 0, 10e16);
        amountDai = bound(amountDai, 1e6, DEFAULT_AMOUNT);
        amountUsdc = bound(amountUsdc, 1e6, DEFAULT_AMOUNT);

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[daiIdx] = amountDai;
        amountsIn[usdcIdx] = amountUsdc;

        uint256[] memory expectedProtocolFees = new uint256[](2);
        expectedProtocolFees[daiIdx] = amountDai.mulUp(protocolFeePercentage);
        expectedProtocolFees[usdcIdx] = amountUsdc.mulUp(protocolFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        vm.prank(lp);
        cowRouter.donate(pool, amountsIn, bytes(""));

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(cowRouter));

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
        // Test new pool balances
        // Test vault balances
        // Test donor balances
        // Check emitted event
    }

    // TODO Pool not accept donation

    /********************************************************
                     setProtocolFeePercentage()
    ********************************************************/
    function testSetProtocolFeePercentageIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        cowRouter.setProtocolFeePercentage(50e16);
    }

    function testSetProtocolFeePercentageCappedAtMax() public {
        // 50% is above the 10% limit.
        uint256 newProtocolFeePercentage = 50e16;
        uint256 protocolFeePercentageLimit = 10e16;

        vm.expectRevert(
            abi.encodeWithSelector(
                ICowRouter.ProtocolFeePercentageAboveLimit.selector,
                newProtocolFeePercentage,
                protocolFeePercentageLimit
            )
        );
        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(50e16);
    }

    function testSetProtocolFeePercentage() public {
        // 5% protocol fee percentage.
        uint256 newProtocolFeePercentage = 5e16;

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(newProtocolFeePercentage);

        assertEq(cowRouter.getProtocolFeePercentage(), newProtocolFeePercentage, "Protocol Fee Percentage is not set");
    }
}
