// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { YieldBearingPoolSwapBase } from "./YieldBearingPoolSwapBase.t.sol";

contract YieldBearingPoolMainnetAave2Test is YieldBearingPoolSwapBase {
    function setUp() public override {
        YieldBearingPoolSwapBase.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "mainnet";
        blockNumber = 20327000;

        // Aave's aDai
        ybToken1 = IERC4626(0xaf270C38fF895EA3f95Ed488CEACe2386F038249);
        // Aave's aUsdt
        ybToken2 = IERC4626(0x862c57d48becB45583AEbA3f489696D22466Ca1b);
        // Donor of DAI tokens
        donorToken1 = 0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf;
        // Donor of USDT tokens
        donorToken2 = 0xF977814e90dA44bFA03b6295A0616a897441aceC;
    }
}
