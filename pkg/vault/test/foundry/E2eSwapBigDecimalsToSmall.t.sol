// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";
import { E2eSwapTest } from "./E2eSwap.t.sol";

contract E2eSwapBigDecimalsToSmallTest is E2eSwapTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    function setUp() public virtual override {
        E2eSwapTest.setUp();
    }

    function setUpTokens() internal override {
        tokenA = new ERC20TestToken("tokenA", "tokenA", 12);
        vm.label(address(tokenA), "tokenA");
        tokenB = new ERC20TestToken("tokenB", "tokenB", 6);
        vm.label(address(tokenB), "tokenB");

        // At this point, poolInitAmountTokenA and poolInitAmountTokenB are not defined, so use poolInitAmount, which
        // is 18 decimals.
        tokenA.mint(lp, 100 * poolInitAmount);
        tokenB.mint(lp, 100 * poolInitAmount);

        vm.startPrank(lp);
        tokenA.approve(address(permit2), MAX_UINT128);
        tokenB.approve(address(permit2), MAX_UINT128);
        permit2.approve(address(tokenA), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(tokenB), address(router), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }
}
