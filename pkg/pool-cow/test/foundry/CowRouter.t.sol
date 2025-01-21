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
        ICowRouter.CowSwapParams memory params = ICowRouter.CowSwapParams({
            tokenIn: dai,
            tokenOut: usdc,
            maxAmountIn: 1e18,
            minAmountOut: 0,
            deadline: type(uint32).max
        });
        cowRouter.swapExactInAndDonateSurplus(pool, params, new uint256[](2), bytes(""));
    }

    function testSwapExactInAndDonateSurplus__Fuzz(
        uint256 daiExactAmountIn,
        uint256 surplusToDonateDai,
        uint256 surplusToDonateUsdc,
        uint256 protocolFeePercentage
    ) public {
        // ProtocolFeePercentage between 0 and 10%.
        protocolFeePercentage = bound(protocolFeePercentage, 0, 10e16);
        surplusToDonateDai = bound(surplusToDonateDai, 1e6, DEFAULT_AMOUNT);
        surplusToDonateUsdc = bound(surplusToDonateUsdc, 1e6, DEFAULT_AMOUNT);
        daiExactAmountIn = bound(daiExactAmountIn, 1e6, DEFAULT_AMOUNT);

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        uint256[] memory surplusToDonate = new uint256[](2);
        surplusToDonate[daiIdx] = surplusToDonateDai;
        surplusToDonate[usdcIdx] = surplusToDonateUsdc;

        uint256[] memory expectedProtocolFees = new uint256[](2);
        expectedProtocolFees[daiIdx] = surplusToDonateDai.mulUp(protocolFeePercentage);
        expectedProtocolFees[usdcIdx] = surplusToDonateUsdc.mulUp(protocolFeePercentage);

        uint256[] memory donatedAmounts = new uint256[](2);
        donatedAmounts[daiIdx] = surplusToDonateDai - expectedProtocolFees[daiIdx];
        donatedAmounts[usdcIdx] = surplusToDonateUsdc - expectedProtocolFees[usdcIdx];

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        vm.expectEmit();
        emit ICowRouter.CoWSwappingAndDonation(
            pool,
            daiExactAmountIn,
            dai,
            daiExactAmountIn, // PoolMock is linear, so amounts in == amounts out
            usdc,
            tokens,
            donatedAmounts,
            expectedProtocolFees,
            bytes("")
        );

        ICowRouter.CowSwapParams memory params = ICowRouter.CowSwapParams({
            tokenIn: dai,
            tokenOut: usdc,
            maxAmountIn: daiExactAmountIn,
            minAmountOut: 0,
            deadline: type(uint32).max
        });

        vm.prank(lp);
        cowRouter.swapExactInAndDonateSurplus(pool, params, surplusToDonate, bytes(""));

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
        assertEq(balancesAfter.lpBpt, balancesBefore.lpBpt, "LP BPT has changed");
        assertEq(balancesAfter.poolSupply, balancesBefore.poolSupply, "BPT supply has changed");

        // Test new pool balances
        assertEq(
            balancesAfter.poolTokens[daiIdx],
            balancesBefore.poolTokens[daiIdx] + surplusToDonateDai - expectedProtocolFees[daiIdx] + daiExactAmountIn,
            "Pool DAI balance is not correct"
        );
        // Since the pool is linear, usdc amount out == dai amount in. In the swap, the pool returned usdc to the
        // caller.
        assertEq(
            balancesAfter.poolTokens[usdcIdx],
            balancesBefore.poolTokens[usdcIdx] + surplusToDonateUsdc - expectedProtocolFees[usdcIdx] - daiExactAmountIn,
            "Pool USDC balance is not correct"
        );

        // Test vault balances
        assertEq(
            balancesAfter.vaultTokens[daiIdx],
            balancesBefore.vaultTokens[daiIdx] + surplusToDonateDai - expectedProtocolFees[daiIdx] + daiExactAmountIn,
            "Vault DAI balance is not correct"
        );
        assertEq(
            balancesAfter.vaultTokens[usdcIdx],
            balancesBefore.vaultTokens[usdcIdx] +
                surplusToDonateUsdc -
                expectedProtocolFees[usdcIdx] -
                daiExactAmountIn,
            "Vault USDC balance is not correct"
        );

        // Test donor balances
        assertEq(
            balancesAfter.lpTokens[daiIdx],
            balancesBefore.lpTokens[daiIdx] - surplusToDonateDai - daiExactAmountIn,
            "LP DAI balance is not correct"
        );
        assertEq(
            balancesAfter.lpTokens[usdcIdx],
            balancesBefore.lpTokens[usdcIdx] - surplusToDonateUsdc + daiExactAmountIn,
            "LP USDC balance is not correct"
        );
    }

    /********************************************************
                  swapExactOutAndDonateSurplus()
    ********************************************************/
    function testSwapExactOutAndDonateSurplusIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        ICowRouter.CowSwapParams memory params = ICowRouter.CowSwapParams({
            tokenIn: dai,
            tokenOut: usdc,
            maxAmountIn: 1e18,
            minAmountOut: 0,
            deadline: type(uint32).max
        });
        cowRouter.swapExactOutAndDonateSurplus(pool, params, new uint256[](2), bytes(""));
    }

    function testSwapExactOutAndDonateSurplus__Fuzz(
        uint256 usdcExactAmountOut,
        uint256 surplusToDonateDai,
        uint256 surplusToDonateUsdc,
        uint256 protocolFeePercentage
    ) public {
        // ProtocolFeePercentage between 0 and 10%.
        protocolFeePercentage = bound(protocolFeePercentage, 0, 10e16);
        surplusToDonateDai = bound(surplusToDonateDai, 1e6, DEFAULT_AMOUNT);
        surplusToDonateUsdc = bound(surplusToDonateUsdc, 1e6, DEFAULT_AMOUNT);
        usdcExactAmountOut = bound(usdcExactAmountOut, 1e6, DEFAULT_AMOUNT);

        vm.prank(admin);
        cowRouter.setProtocolFeePercentage(protocolFeePercentage);

        uint256[] memory surplusToDonate = new uint256[](2);
        surplusToDonate[daiIdx] = surplusToDonateDai;
        surplusToDonate[usdcIdx] = surplusToDonateUsdc;

        uint256[] memory expectedProtocolFees = new uint256[](2);
        expectedProtocolFees[daiIdx] = surplusToDonateDai.mulUp(protocolFeePercentage);
        expectedProtocolFees[usdcIdx] = surplusToDonateUsdc.mulUp(protocolFeePercentage);

        uint256[] memory donatedAmounts = new uint256[](2);
        donatedAmounts[daiIdx] = surplusToDonateDai - expectedProtocolFees[daiIdx];
        donatedAmounts[usdcIdx] = surplusToDonateUsdc - expectedProtocolFees[usdcIdx];

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        vm.expectEmit();
        emit ICowRouter.CoWSwappingAndDonation(
            pool,
            usdcExactAmountOut, // PoolMock is linear, so amounts in == amounts out
            dai,
            usdcExactAmountOut,
            usdc,
            tokens,
            donatedAmounts,
            expectedProtocolFees,
            bytes("")
        );

        ICowRouter.CowSwapParams memory params = ICowRouter.CowSwapParams({
            tokenIn: dai,
            tokenOut: usdc,
            maxAmountIn: MAX_UINT128,
            minAmountOut: usdcExactAmountOut,
            deadline: type(uint32).max
        });

        vm.prank(lp);
        cowRouter.swapExactOutAndDonateSurplus(pool, params, surplusToDonate, bytes(""));

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
        assertEq(balancesAfter.lpBpt, balancesBefore.lpBpt, "LP BPT has changed");
        assertEq(balancesAfter.poolSupply, balancesBefore.poolSupply, "BPT supply has changed");

        // Test new pool balances
        assertEq(
            balancesAfter.poolTokens[daiIdx],
            balancesBefore.poolTokens[daiIdx] + surplusToDonateDai - expectedProtocolFees[daiIdx] + usdcExactAmountOut,
            "Pool DAI balance is not correct"
        );
        // Since the pool is linear, usdc amount out == dai amount in. In the swap, the pool returned usdc to the
        // caller.
        assertEq(
            balancesAfter.poolTokens[usdcIdx],
            balancesBefore.poolTokens[usdcIdx] +
                surplusToDonateUsdc -
                expectedProtocolFees[usdcIdx] -
                usdcExactAmountOut,
            "Pool USDC balance is not correct"
        );

        // Test vault balances
        assertEq(
            balancesAfter.vaultTokens[daiIdx],
            balancesBefore.vaultTokens[daiIdx] + surplusToDonateDai - expectedProtocolFees[daiIdx] + usdcExactAmountOut,
            "Vault DAI balance is not correct"
        );
        assertEq(
            balancesAfter.vaultTokens[usdcIdx],
            balancesBefore.vaultTokens[usdcIdx] +
                surplusToDonateUsdc -
                expectedProtocolFees[usdcIdx] -
                usdcExactAmountOut,
            "Vault USDC balance is not correct"
        );

        // Test donor balances
        assertEq(
            balancesAfter.lpTokens[daiIdx],
            balancesBefore.lpTokens[daiIdx] - surplusToDonateDai - usdcExactAmountOut,
            "LP DAI balance is not correct"
        );
        assertEq(
            balancesAfter.lpTokens[usdcIdx],
            balancesBefore.lpTokens[usdcIdx] - surplusToDonateUsdc + usdcExactAmountOut,
            "LP USDC balance is not correct"
        );
    }

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

        uint256[] memory donatedAmount = new uint256[](2);
        donatedAmount[daiIdx] = amountDai - expectedProtocolFees[daiIdx];
        donatedAmount[usdcIdx] = amountUsdc - expectedProtocolFees[usdcIdx];

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(cowRouter));

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        vm.expectEmit();
        emit ICowRouter.CoWDonation(pool, tokens, donatedAmount, expectedProtocolFees, bytes(""));

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
        assertEq(balancesAfter.lpBpt, balancesBefore.lpBpt, "LP BPT has changed");
        assertEq(balancesAfter.poolSupply, balancesBefore.poolSupply, "BPT supply has changed");

        // Test new pool balances
        assertEq(
            balancesAfter.poolTokens[daiIdx],
            balancesBefore.poolTokens[daiIdx] + amountDai - expectedProtocolFees[daiIdx],
            "Pool DAI balance is not correct"
        );
        assertEq(
            balancesAfter.poolTokens[usdcIdx],
            balancesBefore.poolTokens[usdcIdx] + amountUsdc - expectedProtocolFees[usdcIdx],
            "Pool USDC balance is not correct"
        );

        // Test vault balances
        assertEq(
            balancesAfter.vaultTokens[daiIdx],
            balancesBefore.vaultTokens[daiIdx] + amountDai - expectedProtocolFees[daiIdx],
            "Vault DAI balance is not correct"
        );
        assertEq(
            balancesAfter.vaultTokens[usdcIdx],
            balancesBefore.vaultTokens[usdcIdx] + amountUsdc - expectedProtocolFees[usdcIdx],
            "Vault USDC balance is not correct"
        );

        // Test donor balances
        assertEq(
            balancesAfter.lpTokens[daiIdx],
            balancesBefore.lpTokens[daiIdx] - amountDai,
            "LP DAI balance is not correct"
        );
        assertEq(
            balancesAfter.lpTokens[usdcIdx],
            balancesBefore.lpTokens[usdcIdx] - amountUsdc,
            "LP USDC balance is not correct"
        );
    }

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
