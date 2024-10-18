// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { TokenInfo, SwapKind, PoolSwapParams } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultSwapWithRatesTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using FixedPoint for *;

    // Track the indices for the local dai/wsteth pool.
    uint256 internal daiIdx;
    uint256 internal wstethIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        (daiIdx, wstethIdx) = getSortedIndexes(address(dai), address(wsteth));
    }

    function createPool() internal override returns (address) {
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProvider = deployRateProviderMock();
        // Must match the array passed in, not the sorted index, since buildTokenConfig will do the sorting.
        rateProviders[0] = rateProvider;
        rateProvider.mockRate(mockRate);

        address newPool = address(deployPoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL"));

        factoryMock.registerTestPool(
            newPool,
            vault.buildTokenConfig([address(wsteth), address(dai)].toMemoryArray().asIERC20(), rateProviders),
            poolHooksContract,
            lp
        );

        return newPool;
    }

    function testWithNonPoolCall() public {
        // Only registered pools can emit aux event
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, admin));
        vm.prank(admin);
        vault.emitAuxiliaryEvent("TestEvent", abi.encode(777));
    }

    function testEventEmitted() public {
        uint256 testValue = 777;

        vm.expectEmit();
        emit IVaultEvents.VaultAuxiliary(pool, "TestEvent", abi.encode(testValue));

        vm.prank(admin);
        PoolMock(pool).mockEventFunction(testValue);
    }
}
