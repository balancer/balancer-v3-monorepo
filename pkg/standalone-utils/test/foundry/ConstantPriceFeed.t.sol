// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { ConstantPriceFeed } from "../../contracts/ConstantPriceFeed.sol";

contract ConstantPriceFeedTest is Test {
    ConstantPriceFeed internal _priceFeed;

    function setUp() public virtual {
        _priceFeed = new ConstantPriceFeed();
    }

    function testInitialization() public view {
        assertEq(_priceFeed.version(), 1, "Wrong version");
        assertEq(_priceFeed.decimals(), 18, "Wrong number of decimals");
        assertEq(_priceFeed.description(), "Constant 1.0 Price Feed", "Wrong number of decimals");
    }

    function testGetRoundData() public view {
        (, int256 price, uint256 startTimestamp, uint256 updatedTimestamp, ) = _priceFeed.getRoundData(14);

        _validatePriceFeedData(price, startTimestamp, updatedTimestamp);
    }

    function testConstantPriceFeed() public view {
        (, int256 price, uint256 startTimestamp, uint256 updatedTimestamp, ) = _priceFeed.latestRoundData();

        _validatePriceFeedData(price, startTimestamp, updatedTimestamp);
    }

    function _validatePriceFeedData(int256 price, uint256 startTimestamp, uint256 updatedTimestamp) internal view {
        assertEq(price, int256(FixedPoint.ONE), "Price is not 1");
        assertEq(startTimestamp, block.timestamp, "Wrong start timestamp");
        assertEq(updatedTimestamp, block.timestamp, "Wrong updated timestamp");
    }
}
