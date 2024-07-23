// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { YieldBearingPoolSwapBase } from "./YieldBearingPoolSwapBase.t.sol";

contract YieldBearingPoolMainnetAaveTest is YieldBearingPoolSwapBase {
    function setUp() public override {
        YieldBearingPoolSwapBase.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "mainnet";
        blockNumber = 20327000;

        // Aave's aDai
        ybToken1 = IERC4626(0xaf270C38fF895EA3f95Ed488CEACe2386F038249);
        // Aave's aUsdc
        ybToken2 = IERC4626(0x73edDFa87C71ADdC275c2b9890f5c3a8480bC9E6);
        // Donor of DAI tokens
        donorToken1 = 0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf;
        // Donor of USDC tokens
        donorToken2 = 0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa;
    }
}
