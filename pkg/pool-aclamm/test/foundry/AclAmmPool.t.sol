// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { console2 } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { GyroPoolMath } from "@balancer-labs/v3-pool-gyro/contracts/lib/GyroPoolMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseAclAmmTest } from "./utils/BaseAclAmmTest.sol";
import { AclAmmPool } from "../../contracts/AclAmmPool.sol";
import { AclAmmMath } from "../../contracts/lib/AclAmmMath.sol";

contract AclAmmPoolTest is BaseAclAmmTest {
    using FixedPoint for uint256;

    uint256 internal constant _ITERATIONS = 100;
    uint256 internal constant _DAI_MIN_PRICE = 1e16;
    uint256 internal constant _DAI_MAX_PRICE = 1e20;

    uint256 counter = 1;

    // TODO Remove test. Temporary test to study pool behavior visually.
    function testMultipleSwaps() public {
        uint256 currentPoolPriceDai = _getCurrentDaiPoolPrice();
        uint256 currentMarketPriceDai = currentPoolPriceDai;

        for (uint256 i = 0; i < _ITERATIONS; i++) {
            console2.log("------------------ Iteration: %s ------------------", i);

            // 98 - 105% of current market price.
            currentMarketPriceDai =
                currentMarketPriceDai.mulDown(98e16) +
                currentMarketPriceDai.mulDown(bound(_random(), 0, 7e16));

            uint256 tokenInIndex;
            uint256 tokenOutIndex;

            if (currentPoolPriceDai < currentMarketPriceDai) {
                tokenInIndex = usdcIdx;
                tokenOutIndex = daiIdx;
            } else {
                tokenInIndex = daiIdx;
                tokenOutIndex = usdcIdx;
            }

            console2.log("Current pool price:   %s", currentPoolPriceDai);
            console2.log("Current market price: %s", currentMarketPriceDai);
            console2.log("Token in: ", (tokenInIndex == daiIdx) ? "DAI" : "USDC");
            console2.log("Token out: ", (tokenOutIndex == daiIdx) ? "DAI" : "USDC");

            uint256 swapAmount = _calculateSwapInForMarketPrice(currentMarketPriceDai, tokenInIndex);

            if (swapAmount != 0) {
                vm.prank(bob);
                router.swapSingleTokenExactIn(
                    pool,
                    IERC20(tokenInIndex == daiIdx ? dai : usdc),
                    IERC20(tokenOutIndex == daiIdx ? dai : usdc),
                    swapAmount,
                    0,
                    block.timestamp,
                    false,
                    bytes("")
                );
            }

            currentPoolPriceDai = _getCurrentDaiPoolPrice();
            vm.warp(block.timestamp + 1 hours);
        }
    }

    function _getCurrentDaiPoolPrice() internal view returns (uint256) {
        uint256[] memory virtualBalances = AclAmmPool(pool).getLastVirtualBalances();

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(pool);

        return (balances[usdcIdx] + virtualBalances[usdcIdx]).divDown(balances[daiIdx] + virtualBalances[daiIdx]);
    }

    function _calculateSwapInForMarketPrice(
        uint256 currentMarketPriceDai,
        uint256 tokenInIndex
    ) internal view returns (uint256) {
        uint256[] memory virtualBalances = AclAmmPool(pool).getLastVirtualBalances();
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(pool);

        // uint256 currentPoolPriceDai = _getCurrentDaiPoolPrice();

        console2.log("balances[0]:              %s", balances[0]);
        console2.log("balances[1]:              %s", balances[1]);

        uint256 invariant = (balances[0] + virtualBalances[0]).mulDown(balances[1] + virtualBalances[1]);

        {
            // Price range calculation
            uint256 PMaxDai = invariant.divDown(virtualBalances[daiIdx].mulDown(virtualBalances[daiIdx]));
            uint256 PMinDai = virtualBalances[usdcIdx].mulDown(virtualBalances[usdcIdx]).divDown(invariant);

            console2.log("PMaxDai:                 %s", PMaxDai);
            console2.log("PMinDai:                 %s", PMinDai);
            console2.log("PriceRange:              %s", PMaxDai.divDown(PMinDai));
        }

        uint256 invariantFactor;
        if (tokenInIndex == daiIdx) {
            invariantFactor = invariant.divDown(currentMarketPriceDai);
        } else {
            invariantFactor = invariant.mulDown(currentMarketPriceDai);
        }

        // Temporarily using sqrt lib with decimals from Gyro.
        uint256 sqrtBaskhara = GyroPoolMath.sqrt(invariantFactor, 3);
        uint256 finalBalance = balances[tokenInIndex] + virtualBalances[tokenInIndex];

        console2.log("sqrtBaskhara:             %s", sqrtBaskhara);
        console2.log("finalBalance:             %s", finalBalance);

        if (sqrtBaskhara < finalBalance) {
            return 0;
        }

        uint256 amountIn = sqrtBaskhara - finalBalance;
        uint256 tokenOutIndex = tokenInIndex == daiIdx ? usdcIdx : daiIdx;
        uint256 expectedAmountOut = balances[tokenOutIndex] +
            virtualBalances[tokenOutIndex] -
            invariant.divDown(finalBalance + amountIn);

        if (expectedAmountOut > balances[tokenOutIndex] || expectedAmountOut <= 1) {
            return 0;
        }

        return amountIn;
    }

    function _random() private returns (uint256) {
        counter++;
        return uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, counter)));
    }

    function testGetCurrentSqrtQ0() public view {
        uint256 sqrtQ0 = AclAmmPool(pool).getCurrentSqrtQ0();
        assertEq(sqrtQ0, _DEFAULT_SQRT_Q0, "Invalid default sqrtQ0");
    }

    function testSetSqrtQ0() public {
        uint256 newSqrtQ0 = 2e18;
        uint256 startTime = block.timestamp;
        uint256 duration = 1 hours;
        uint256 endTime = block.timestamp + duration;

        uint256 startSqrtQ0 = AclAmmPool(pool).getCurrentSqrtQ0();
        vm.prank(admin);
        AclAmmPool(pool).setSqrtQ0(newSqrtQ0, startTime, endTime);

        skip(duration / 2);
        uint256 sqrtQ0 = AclAmmPool(pool).getCurrentSqrtQ0();
        uint256 mathSqrtQ0 = AclAmmMath.calculateSqrtQ0(block.timestamp, startSqrtQ0, newSqrtQ0, startTime, endTime);

        assertEq(sqrtQ0, mathSqrtQ0, "SqrtQ0 not updated correctly");

        skip(duration / 2 + 1);
        sqrtQ0 = AclAmmPool(pool).getCurrentSqrtQ0();
        assertEq(sqrtQ0, newSqrtQ0, "SqrtQ0 does not match new value");
    }
}
