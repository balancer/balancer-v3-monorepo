// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { YieldBearingPoolSwapBase } from "./YieldBearingPoolSwapBase.t.sol";

contract YieldBearingPoolMainnetGearboxTest is YieldBearingPoolSwapBase {
    function setUp() public override {
        YieldBearingPoolSwapBase.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "mainnet";
        blockNumber = 20327000;

        // Gearbox's gUsdc
        ybToken1 = IERC4626(0xda00000035fef4082F78dEF6A8903bee419FbF8E);
        // Gearbox's gWeth
        ybToken2 = IERC4626(0xda0002859B2d05F66a753d8241fCDE8623f26F4f);
        // Donor of USDC
        donorToken1 = 0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa;
        // Donor of Weth
        donorToken2 = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
    }
}
