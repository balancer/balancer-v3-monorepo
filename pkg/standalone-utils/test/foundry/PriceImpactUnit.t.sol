// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { PriceImpactHelperMock } from "../../contracts/test/PriceImpactHelperMock.sol";

contract PriceImpactUnitTest is BaseVaultTest {
    PriceImpactHelperMock priceImpactHelper;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        priceImpactHelper = new PriceImpactHelperMock(vault, router);
    }

    function testMaxNegativeIndex__Fuzz(int256[10] memory arrayRaw, uint256 maxIndex) public view {
        int256[] memory array = new int256[](arrayRaw.length);

        maxIndex = bound(maxIndex, 0, arrayRaw.length - 1);
        for (uint256 i = 0; i < arrayRaw.length; i++) {
            array[i] = bound(arrayRaw[i], type(int256).min, -2);
        }
        array[maxIndex] = -1;

        uint256 expectedIndex = priceImpactHelper.maxNegativeIndex(array);
        assertEq(expectedIndex, maxIndex, "expected max value index wrong");
    }

    function testMinPositiveIndex__Fuzz(int256[10] memory arrayRaw, uint256 minIndex) public view {
        int256[] memory array = new int256[](arrayRaw.length);

        minIndex = bound(minIndex, 0, arrayRaw.length - 1);
        for (uint256 i = 0; i < arrayRaw.length; i++) {
            array[i] = bound(arrayRaw[i], 2, type(int256).max);
        }
        array[minIndex] = 1;

        uint256 expectedIndex = priceImpactHelper.minPositiveIndex(array);
        assertEq(expectedIndex, minIndex, "expected min value index wrong");
    }

    function testQueryAddLiquidityUnbalancedForTokenDeltas__Fuzz(
        int256[10] memory deltasRaw,
        uint256 length,
        uint256 tokenIndex,
        uint256 mockResult
    ) public {
        length = bound(length, 2, deltasRaw.length);
        tokenIndex = bound(tokenIndex, 0, length - 1);
        mockResult = bound(mockResult, 0, MAX_UINT128);

        int256[] memory deltas = new int256[](length);
        for (uint256 i = 0; i < length; i++) {
            deltas[i] = bound(deltasRaw[i], type(int256).min + 1, type(int256).max);
        }

        int256 delta = deltas[tokenIndex];
        if (delta == 0) {
            assertEq(
                priceImpactHelper.queryAddLiquidityUnbalancedForTokenDeltas(pool, tokenIndex, deltas, address(this)),
                0,
                "queryAddLiquidityUnbalancedForTokenDeltas should return 0"
            );
        } else {
            uint256[] memory mockDeltas = new uint256[](length);
            mockDeltas[tokenIndex] = uint256(delta > 0 ? delta : -delta);

            vm.mockCall(
                address(router),
                abi.encodeWithSelector(
                    router.queryAddLiquidityUnbalanced.selector,
                    pool,
                    mockDeltas,
                    address(this),
                    ""
                ),
                abi.encode(mockResult)
            );

            int256 expectedResult = priceImpactHelper.queryAddLiquidityUnbalancedForTokenDeltas(
                pool,
                tokenIndex,
                deltas,
                address(this)
            );

            assertEq(
                expectedResult,
                delta > 0 ? int256(mockResult) : -int256(mockResult),
                "expected queryAddLiquidityUnbalancedForTokenDeltas result is wrong"
            );
        }
    }
}
