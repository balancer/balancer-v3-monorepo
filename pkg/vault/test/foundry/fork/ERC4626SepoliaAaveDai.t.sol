// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ERC4626WrapperBaseTest } from "./ERC4626WrapperBase.t.sol";

contract ERC4626SepoliaAaveDaiTest is ERC4626WrapperBaseTest {
    function setUp() public override {
        ERC4626WrapperBaseTest.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "sepolia";
        blockNumber = 6288761;

        // Aave's static aDAI
        wrapper = IERC4626(0xDE46e43F46ff74A23a65EBb0580cbe3dFE684a17);
        // Donor of DAI tokens
        underlyingDonor = 0x4d02aF17A29cdA77416A1F60Eae9092BB6d9c026;
        amountToDonate = 1e6 * 1e18;
    }
}
