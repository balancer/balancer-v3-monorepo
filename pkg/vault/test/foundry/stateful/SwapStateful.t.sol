// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";
import { OperationsHandler } from "./utils/OperationsHandler.sol";

contract SwapStatefulTest is BaseVaultTest {
    OperationsHandler internal handler;

    uint256 internal initialPoolInvariant;

    function setUp() public override {
        BaseVaultTest.setUp();

        (uint256 daiIdx, uint256 usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        handler = new OperationsHandler(vault, router, alice, pool, dai, usdc, daiIdx, usdcIdx);
        // An invariant test randomly calls one public function from any contract created by setUp(), which include
        // tokens, pools, vault, etc. When we call targetContract(), we restrict the functions to be called to the
        // target contract.
        targetContract(address(handler));

        (, , , uint256[] memory lastBalancesLiveScaled18) = vault.getPoolTokenInfo(pool);
        initialPoolInvariant = IBasePool(pool).computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_UP);
    }

    function invariantSwaps__Stateful() public view {
        (, , , uint256[] memory lastBalancesLiveScaled18) = vault.getPoolTokenInfo(pool);
        uint256 newInvariant = IBasePool(pool).computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_DOWN);

        assertGe(newInvariant, initialPoolInvariant, "Pool Invariant decreased!");
    }
}
