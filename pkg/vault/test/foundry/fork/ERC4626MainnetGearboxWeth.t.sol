// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ERC4626WrapperBaseTest } from "./ERC4626WrapperBase.t.sol";

contract ERC4626MainnetGearboxWethTest is ERC4626WrapperBaseTest {
    function setUp() public override {
        ERC4626WrapperBaseTest.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "mainnet";
        blockNumber = 20413389;

        // Gearbox's gWeth
        wrapper = IERC4626(0xda0002859B2d05F66a753d8241fCDE8623f26F4f);
        // Donor of Weth
        underlyingDonor = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
        amountToDonate = 1e5 * 1e18;
    }
}
