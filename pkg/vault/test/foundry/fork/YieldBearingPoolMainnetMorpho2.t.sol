// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { YieldBearingPoolSwapBase } from "./YieldBearingPoolSwapBase.t.sol";

contract YieldBearingPoolMainnetMorpho2Test is YieldBearingPoolSwapBase {
    function setUp() public override {
        YieldBearingPoolSwapBase.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "mainnet";
        blockNumber = 20327000;

        // Morpho's maWBTC
        ybToken1 = IERC4626(0xd508F85F1511aAeC63434E26aeB6d10bE0188dC7);
        // Morpho's maUSDC
        ybToken2 = IERC4626(0xA5269A8e31B93Ff27B887B56720A25F844db0529);
        // Donor of WBTC tokens
        donorToken1 = 0x5Ee5bf7ae06D1Be5997A1A72006FE6C607eC6DE8;
        // Donor of USDC tokens
        donorToken2 = 0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa;
    }
}
