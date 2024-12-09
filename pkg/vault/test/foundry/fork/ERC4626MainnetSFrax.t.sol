// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ERC4626WrapperBaseTest } from "./ERC4626WrapperBase.t.sol";

contract ERC4626MainnetSFraxTest is ERC4626WrapperBaseTest {
    function setUp() public override {
        ERC4626WrapperBaseTest.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "mainnet";
        blockNumber = 20327000;

        // sFrax
        wrapper = IERC4626(0xA663B02CF0a4b149d2aD41910CB81e23e1c41c32);
        // Donor of FRAX tokens
        underlyingDonor = 0xcE6431D21E3fb1036CE9973a3312368ED96F5CE7;
        amountToDonate = 1e6 * 1e18;
    }
}
