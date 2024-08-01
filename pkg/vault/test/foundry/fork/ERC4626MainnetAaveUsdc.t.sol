// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ERC4626WrapperBaseTest } from "./ERC4626WrapperBase.t.sol";

contract ERC4626MainnetAaveUsdcTest is ERC4626WrapperBaseTest {
    function setUp() public override {
        ERC4626WrapperBaseTest.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "mainnet";
        blockNumber = 20327000;

        // Aave's aUsdc
        wrapper = IERC4626(0x73edDFa87C71ADdC275c2b9890f5c3a8480bC9E6);
        // Donor of USDC tokens
        underlyingDonor = 0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa;
        amountToDonate = 1e6 * 1e6;
    }
}
