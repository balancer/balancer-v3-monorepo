// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { YieldBearingPoolSwapBase } from "./YieldBearingPoolSwapBase.t.sol";

contract YieldBearingPoolMainnetMorphoTest is YieldBearingPoolSwapBase {
    function setUp() public override {
        YieldBearingPoolSwapBase.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "mainnet";
        blockNumber = 20327000;

        // Morpho's maWBTC
        ybToken1 = IERC4626(0xd508F85F1511aAeC63434E26aeB6d10bE0188dC7);
        // Morpho's maWETH
        ybToken2 = IERC4626(0x490BBbc2485e99989Ba39b34802faFa58e26ABa4);
        // Donor of WBTC tokens
        donorToken1 = 0x5Ee5bf7ae06D1Be5997A1A72006FE6C607eC6DE8;
        // Donor of WETH tokens
        donorToken2 = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
    }
}
