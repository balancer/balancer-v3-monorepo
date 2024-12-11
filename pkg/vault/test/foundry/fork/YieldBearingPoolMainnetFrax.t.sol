// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { YieldBearingPoolSwapBase } from "./YieldBearingPoolSwapBase.t.sol";

contract YieldBearingPoolMainnetFraxTest is YieldBearingPoolSwapBase {
    function setUp() public override {
        YieldBearingPoolSwapBase.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "mainnet";
        blockNumber = 20327000;

        // sFrax
        ybToken1 = IERC4626(0xA663B02CF0a4b149d2aD41910CB81e23e1c41c32);
        // sfrxEth
        ybToken2 = IERC4626(0xac3E018457B222d93114458476f3E3416Abbe38F);
        // Donor of Frax tokens
        donorToken1 = 0xcE6431D21E3fb1036CE9973a3312368ED96F5CE7;
        // Donor of frxEth tokens
        donorToken2 = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    }
}
