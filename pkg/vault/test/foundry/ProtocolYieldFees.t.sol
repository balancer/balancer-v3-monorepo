// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultMain } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { FactoryWidePauseWindow } from "../../contracts/factories/FactoryWidePauseWindow.sol";
import { PoolFactoryMock } from "../../contracts/test/PoolFactoryMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract ProtocolYieldFeesTest is BaseVaultTest {
    using ArrayHelpers for *;

    RateProviderMock wstETHRateProvider;
    RateProviderMock daiRateProvider;

    function setUp() public override {
        BaseVaultTest.setUp();
    }

    // Create wsteth / dai pool, with rate providers on wsteth (non-exempt), and dai (exempt)
    function createPool() internal override returns (address) {
        wstETHRateProvider = new RateProviderMock();
        daiRateProvider = new RateProviderMock();

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        bool[] memory yieldExemptFlags = new bool[](2);

        rateProviders[0] = wstETHRateProvider;
        rateProviders[1] = daiRateProvider;
        yieldExemptFlags[1] = true;

        PoolMock newPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 Pool",
            "ERC20POOL",
            [address(wsteth), address(dai)].toMemoryArray().asIERC20(),
            rateProviders,
            yieldExemptFlags,
            true,
            365 days,
            address(0)
        );
        vm.label(address(newPool), "pool");
        return address(newPool);
    }
}
