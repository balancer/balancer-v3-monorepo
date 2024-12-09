// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ERC4626WrapperBaseTest } from "./ERC4626WrapperBase.t.sol";

contract ERC4626MainnetSFrxEthTest is ERC4626WrapperBaseTest {
    function setUp() public override {
        ERC4626WrapperBaseTest.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "mainnet";
        blockNumber = 21365318;

        // sfrxEth
        wrapper = IERC4626(0xac3E018457B222d93114458476f3E3416Abbe38F);
        // Donor of frxEth tokens
        underlyingDonor = 0xac3E018457B222d93114458476f3E3416Abbe38F;
        amountToDonate = 5e4 * 1e18;
    }
}
