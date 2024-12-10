// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ERC4626WrapperBaseTest } from "./ERC4626WrapperBase.t.sol";

contract ERC4626MainnetMorphoSteakhouseWUSDLTest is ERC4626WrapperBaseTest {
    function setUp() public override {
        ERC4626WrapperBaseTest.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "mainnet";
        blockNumber = 21374035;

        // Morpho's Steakhouse wUSDL
        wrapper = IERC4626(0xbEEFC01767ed5086f35deCb6C00e6C12bc7476C1);
        // Donor of wUSDL tokens
        underlyingDonor = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
        amountToDonate = 1e6 * 1e18;
    }
}
