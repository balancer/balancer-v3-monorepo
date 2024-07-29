// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ERC4626WrapperBaseTest } from "./ERC4626WrapperBase.t.sol";

contract ERC4626MainnetAaveDaiTest is ERC4626WrapperBaseTest {
    function setUp() public override {
        ERC4626WrapperBaseTest.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "mainnet";
        blockNumber = 20327000;

        // Aave's aDai
        wrapper = IERC4626(0xaf270C38fF895EA3f95Ed488CEACe2386F038249);
        // Donor of DAI tokens
        underlyingDonor = 0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf;
        amountToDonate = 1e6 * 1e18;
    }
}
