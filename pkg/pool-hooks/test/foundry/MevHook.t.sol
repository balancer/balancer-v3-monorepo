// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IMevHook } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/IMevHook.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { MevHook } from "../../contracts/MevHook.sol";

contract MevHookTest is BaseVaultTest {
    IMevHook private _mevHook;

    function setUp() public override {
        super.setUp();
    }

    function createHook() internal override returns (address) {
        address mevHook = address(new MevHook(IVault(address(vault))));
        _mevHook = IMevHook(mevHook);
        vm.label(mevHook, "Mev Hook");
        return mevHook;
    }

    function testIsMevTaxEnabledStartingState() public {
        assertFalse(_mevHook.isMevTaxEnabled(), "Mev Tax is enabled after hook creation.");
    }
}
