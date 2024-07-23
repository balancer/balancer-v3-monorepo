// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { YieldBearingPoolSwapBase } from "./YieldBearingPoolSwapBase.t.sol";

contract YieldBearingPoolSepoliaAaveTest is YieldBearingPoolSwapBase {
    function setUp() public override {
        YieldBearingPoolSwapBase.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "sepolia";
        blockNumber = 6288761;

        // Aave's static aUSDC
        ybToken1 = IERC4626(0x8A88124522dbBF1E56352ba3DE1d9F78C143751e);
        // Aave's static aDAI
        ybToken2 = IERC4626(0xDE46e43F46ff74A23a65EBb0580cbe3dFE684a17);
        // Donor of USDC
        donorToken1 = 0x0F97F07d7473EFB5c846FB2b6c201eC1E316E994;
        // Donor of DAI
        donorToken2 = 0x4d02aF17A29cdA77416A1F60Eae9092BB6d9c026;
    }
}
