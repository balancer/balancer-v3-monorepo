// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StablePool } from "@balancer-labs/v3-pool-stable/contracts/StablePool.sol";
import { StablePoolFactory } from "@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol";

import { ERC4626RateProvider } from "../../../contracts/test/ERC4626RateProvider.sol";
import { BaseVaultTest } from "../utils/BaseVaultTest.sol";
import { YieldBearingPoolSwapQueryVsActualBase } from "./YieldBearingPoolSwapQueryVsActualBase.t.sol";

contract YieldBearingPoolSepoliaAaveTest is YieldBearingPoolSwapQueryVsActualBase {
    function setUp() public override {
        YieldBearingPoolSwapQueryVsActualBase.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "sepolia";
        blockNumber = 6288761;

        ybToken1 = IERC4626(0x8A88124522dbBF1E56352ba3DE1d9F78C143751e);
        ybToken2 = IERC4626(0xDE46e43F46ff74A23a65EBb0580cbe3dFE684a17);
        donorToken1 = 0x0F97F07d7473EFB5c846FB2b6c201eC1E316E994;
        donorToken2 = 0x4d02aF17A29cdA77416A1F60Eae9092BB6d9c026;
    }
}
