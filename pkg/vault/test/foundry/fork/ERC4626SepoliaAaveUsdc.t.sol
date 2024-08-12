// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ERC4626WrapperBaseTest } from "./ERC4626WrapperBase.t.sol";

contract ERC4626SepoliaAaveUsdcTest is ERC4626WrapperBaseTest {
    function setUp() public override {
        ERC4626WrapperBaseTest.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "sepolia";
        blockNumber = 6288761;

        // Aave's static aUSDC
        wrapper = IERC4626(0x8A88124522dbBF1E56352ba3DE1d9F78C143751e);
        // Donor of USDC
        underlyingDonor = 0x0F97F07d7473EFB5c846FB2b6c201eC1E316E994;
        amountToDonate = 1e6 * 1e6;
    }
}
