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
import { YieldBearingPoolSwapBase } from "./YieldBearingPoolSwapBase.t.sol";

contract YieldBearingPoolMainnetYearnTest is YieldBearingPoolSwapBase {
    function setUp() public override {
        YieldBearingPoolSwapBase.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "mainnet";
        blockNumber = 20327000;

        // Yearn's yvWeth
        ybToken1 = IERC4626(0xc56413869c6CDf96496f2b1eF801fEDBdFA7dDB0);
        // Yearn's yvUSDC
        ybToken2 = IERC4626(0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204);
        // Donor of Weth
        donorToken1 = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
        // Donor of USDC
        donorToken2 = 0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa;
    }
}
