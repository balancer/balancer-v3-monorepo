// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/console.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { StableSurgeMedianMathMock } from "../../contracts/test/StableSurgeMedianMathMock.sol";

contract StableSurgeMedianMathTest is BaseVaultTest {
    uint256 constant MIN_TOKENS = 2;
    uint256 constant MAX_TOKENS = 8;

    StableSurgeMedianMathMock stableSurgeMedianMathMock = new StableSurgeMedianMathMock();

    function testCalculateImbalance() public view {
        uint256[] memory balances = new uint256[](8);
        uint256[] memory diffs = new uint256[](balances.length);

        balances[0] = 1000;
        balances[1] = 12567;
        balances[2] = 100;
        balances[3] = 50;
        balances[4] = 199000;
        balances[5] = 101;
        balances[6] = 500;
        balances[7] = 2500;

        uint256 expectedMedian = 750;

        uint256 totalDiffs = 0;
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < balances.length; i++) {
            totalBalance += balances[i];

            diffs[i] = stableSurgeMedianMathMock.absSub(balances[i], expectedMedian);
            totalDiffs += diffs[i];
        }

        uint256 expectedImbalance = (totalDiffs * 1e18) / totalBalance;

        uint256 imbalance = stableSurgeMedianMathMock.calculateImbalance(balances);
        assertEq(imbalance, expectedImbalance, "Imbalance is not correct");
    }

    function testFindMedianWithEvenTokens() public view {
        uint256 tokensCount = 4;
        uint256[] memory balances = new uint256[](tokensCount);
        for (uint256 i = 0; i < balances.length; i++) {
            balances[i] = 100 + 1000 * i;
        }

        uint256 expectedMedian = (balances[1] + balances[2]) / 2;
        uint256 median = stableSurgeMedianMathMock.findMedian(balances);

        assertEq(median, expectedMedian, "Median is not correct");
    }

    function testFindMedianWithOddTokens() public view {
        uint256 tokensCount = 3;
        uint256[] memory balances = new uint256[](tokensCount);
        for (uint256 i = 0; i < balances.length; i++) {
            balances[i] = 100 + 1000 * i;
        }

        uint256 median = stableSurgeMedianMathMock.findMedian(balances);

        assertEq(median, balances[1], "Median is not correct");
    }

    function testAbsSub() public view {
        assertEq(stableSurgeMedianMathMock.absSub(10, 5), 5, "abs(10 - 5) != 5");
        assertEq(stableSurgeMedianMathMock.absSub(5, 10), 5, "abs(5 - 10) != 5");
        assertEq(stableSurgeMedianMathMock.absSub(0, 0), 0, "abs(0 - 0) != 0");
        assertEq(stableSurgeMedianMathMock.absSub(0, 1), 1, "abs(0 - 1) != 1");
        assertEq(stableSurgeMedianMathMock.absSub(1, 0), 1, "abs(1 - 0) != 1");
        assertEq(
            stableSurgeMedianMathMock.absSub(MAX_UINT256, 1),
            MAX_UINT256 - 1,
            "abs(MAX_UINT256 - 1) != MAX_UINT256 - 1"
        );
        assertEq(
            stableSurgeMedianMathMock.absSub(1, MAX_UINT256),
            MAX_UINT256 - 1,
            "abs(1 - MAX_UINT256) != MAX_UINT256 - 1"
        );
        assertEq(stableSurgeMedianMathMock.absSub(MAX_UINT256, 0), MAX_UINT256, "abs(MAX_UINT256 - 0) != MAX_UINT256");
        assertEq(stableSurgeMedianMathMock.absSub(0, MAX_UINT256), MAX_UINT256, "abs(0 - MAX_UINT256) != MAX_UINT256");
    }
}
