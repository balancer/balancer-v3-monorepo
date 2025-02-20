// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { console2 } from "forge-std/Test.sol";

import { FixedPoint } from "@balancer-labs/v2-vault/contracts/math/FixedPoint.sol";

import { BaseAclAmmTest } from "./utils/BaseAclAmmTest.sol";

contract AclAmmPoolTest is BaseAclAmmTest {
    using FixedPoint for uint256;

    uint256 internal constant _ITERATION = 100;
    uint256 internal constant _DAI_MIN_PRICE = 1e16;
    uint256 internal constant _DAI_MAX_PRICE = 1e20;

    function testMultipleSwaps() public {
        uint256 currentPoolPriceDai = _getCurrentDaiPoolPrice();
        uint256 currentMarketPriceDai = currentPoolPriceDai
        
        for (uint256 i = 0; i < _ITERATIONS; i++) {
            // 90 - 110% of current market price.
            uint256 currentMarketPriceDai = currentMarketPriceDai.mulDown(90e16) + currentMarketPriceDai.mulDown(vm.randomUint(0, 20e16)); 
            uint256 swapAmount = vm.randomUint(1e18, 100e18);

            console2.log("Current market price: %s", currentMarketPrice);
            console2.log("Swap amount: %s", swapAmount);
        }
    }

    function _getCurrentDaiPoolPrice() internal view returns (uint256) {
        uint256[] memory virtualBalances = AclAmmPool(pool).getLastVirtualBalances();
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(pool);

        return (balances[usdcIdx] + virtualBalances[usdcIdx]).divDown(balances[daiIdx] + virtualBalances[daiIdx]);
    }

    function _calculateSwapInDaiForMarketPrice(uint256 currentMarketPriceDai) internal view returns (uint256) {
        uint256 currentPoolPriceDai = _getCurrentDaiPoolPrice();
        if (currentPoolPriceDai > currentMarketPriceDai) {
            // DAI price has decreased, so the market will buy USDC and sell DAI.
            return currentMarketPriceDai.mulDown(1e18).divDown(currentPoolPriceDai);
        } else {
            // DAI price has increased, so the market will buy DAI and sell USDC.
            return currentPoolPriceDai.mulDown(1e18).divDown(currentMarketPriceDai);
        }
    }
        return currentMarketPriceDai.mulDown(1e18).divDown(currentPoolPriceDai);
    }
}
