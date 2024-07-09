// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { SwapKind, SwapParams } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { VaultExplorer } from "../../contracts/VaultExplorer.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultExplorerTest is BaseVaultTest {
    VaultExplorer internal explorer;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        explorer = new VaultExplorer(vault);
    }

    function testGetVaultContracts() public view {
        assertEq(explorer.getVault(), address(vault), "Vault address mismatch");
        assertEq(explorer.getVaultExtension(), vault.getVaultExtension(), "Vault Extension address mismatch");
        assertEq(explorer.getVaultAdmin(), vault.getVaultAdmin(), "Vault Admin address mismatch");
        assertEq(explorer.getAuthorizer(), address(vault.getAuthorizer()), "Authorizer address mismatch");
        assertEq(
            explorer.getProtocolFeeController(),
            address(vault.getProtocolFeeController()),
            "Protocol Fee Controller address mismatch"
        );
    }

    function testPoolTokenCount() public view {
        (uint256 tokenCountVault, uint256 tokenIndexVault) = vault.getPoolTokenCountAndIndexOfToken(pool, dai);
        (uint256 tokenCountExplorer, uint256 tokenIndexExplorer) = explorer.getPoolTokenCountAndIndexOfToken(pool, dai);

        assertEq(tokenCountExplorer, tokenCountVault, "Token count mismatch");
        assertEq(tokenIndexExplorer, tokenIndexVault, "Token index mismatch");
    }

    function testUnlocked() public {
        assertFalse(explorer.isUnlocked(), "Should be locked");

        vault.manualSetIsUnlocked(true);
        assertTrue(explorer.isUnlocked(), "Should be unlocked");
    }

    function testNonzeroDeltaCount() public {
        assertEq(explorer.getNonzeroDeltaCount(), 0, "Wrong initial non-zero delta count");

        vault.manualSetNonZeroDeltaCount(47);
        assertEq(explorer.getNonzeroDeltaCount(), 47, "Wrong non-zero delta count");
    }

    function testGetReservesOf() public {
        vault.manualSetIsUnlocked(true);
        vault.manualSetReservesOf(dai, defaultAmount);

        dai.mint(address(vault), defaultAmount);
        assertEq(vault.getReservesOf(dai), defaultAmount);
        assertEq(explorer.getReservesOf(dai), defaultAmount);
    }
}
