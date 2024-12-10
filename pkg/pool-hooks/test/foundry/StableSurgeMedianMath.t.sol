// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { Arrays } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/Arrays.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { StableSurgeMedianMathMock } from "../../contracts/test/StableSurgeMedianMathMock.sol";

contract StableSurgeMedianMathTest is BaseVaultTest {
    using Arrays for uint256[];
    using InputHelpers for uint256[];

    uint256 constant MIN_TOKENS = 2;
    uint256 constant MAX_TOKENS = 8;

    StableSurgeMedianMathMock stableSurgeMedianMathMock = new StableSurgeMedianMathMock();

    function testAbsSub__Fuzz(uint256 a, uint256 b) public view {
        a = bound(a, 0, MAX_UINT256);
        b = bound(b, 0, MAX_UINT256);

        uint256 result;
        if (a > b) {
            result = a - b;
        } else {
            result = b - a;
        }

        assertEq(stableSurgeMedianMathMock.absSub(a, b), result, "absSub(a,b) has incorrect result");
        assertEq(stableSurgeMedianMathMock.absSub(b, a), result, "absSub(b, a) has incorrect result");
    }

    function testAbsSubWithMinAndMaxValues() public view {
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

    function testFindMedian_Fuzz(uint256 length, uint256[8] memory rawBalances) public view {
        length = bound(length, MIN_TOKENS, MAX_TOKENS);
        uint256[] memory balances = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            balances[i] = bound(rawBalances[i], 0, MAX_UINT128);
        }

        uint256[] memory sortedBalances = balances.sort();
        sortedBalances.ensureSortedAmounts();

        uint256 expectedMedian;
        uint256 mid = length / 2;
        if (length % 2 == 0) {
            expectedMedian = (sortedBalances[mid - 1] + sortedBalances[mid]) / 2;
        } else {
            expectedMedian = sortedBalances[mid];
        }

        uint256 median = stableSurgeMedianMathMock.findMedian(balances);
        assertEq(median, expectedMedian, "Median is not correct");
    }

    function testCalculateImbalance__Fuzz(uint256 length, uint256[8] memory rawBalances) public view {
        length = bound(length, MIN_TOKENS, MAX_TOKENS);
        uint256[] memory balances = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            balances[i] = bound(rawBalances[i], 1, MAX_UINT128);
        }

        uint256 median = stableSurgeMedianMathMock.findMedian(balances);
        uint256 totalBalance = 0;
        uint256 totalDiffs = 0;

        for (uint256 i = 0; i < balances.length; i++) {
            totalBalance += balances[i];

            totalDiffs += stableSurgeMedianMathMock.absSub(balances[i], median);
        }

        uint256 expectedImbalance = (totalDiffs * 1e18) / totalBalance;

        uint256 imbalance = stableSurgeMedianMathMock.calculateImbalance(balances);
        assertEq(imbalance, expectedImbalance, "Imbalance is not correct");
    }
}
