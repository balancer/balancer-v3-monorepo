// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultTypes.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultSwapWithRatesTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for *;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function createPool() internal override returns (address) {
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProvider = new RateProviderMock();
        rateProviders[0] = rateProvider;
        rateProvider.mockRate(mockRate);

        return
            address(
                new PoolMock(
                    IVault(address(vault)),
                    "ERC20 Pool",
                    "ERC20POOL",
                    [address(wsteth), address(dai)].toMemoryArray().asIERC20(),
                    rateProviders,
                    true,
                    365 days,
                    address(0)
                )
            );
    }

    function testInitializePoolWithRate() public {
        // mock pool invariant is just a sum of all balances
        assertEq(
            PoolMock(pool).balanceOf(lp),
            defaultAmount + defaultAmount.mulDown(mockRate) - 1e6,
            "Invalid amount of BPT"
        );
    }

    function testInitialRateProviderState() public {
        (, , , IRateProvider[] memory rateProviders) = vault.getPoolTokenInfo(address(pool));

        assertEq(address(rateProviders[0]), address(rateProvider));
        assertEq(address(rateProviders[1]), address(0));
    }

    function testSwapGivenInWithRate() public {
        uint256 rateAdjustedLimit = defaultAmount.divDown(mockRate);
        uint256 rateAdjustedAmount = defaultAmount.mulDown(mockRate);

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.SwapParams({
                    kind: SwapKind.GIVEN_IN,
                    amountGivenScaled18: defaultAmount,
                    balancesScaled18: [rateAdjustedAmount, defaultAmount].toMemoryArray(),
                    indexIn: 1,
                    indexOut: 0,
                    sender: address(router),
                    userData: bytes("")
                })
            )
        );

        vm.prank(bob);
        router.swapExactIn(
            address(pool),
            dai,
            wsteth,
            defaultAmount,
            rateAdjustedLimit,
            type(uint256).max,
            false,
            bytes("")
        );
    }

    function testSwapGivenOutWithRate() public {
        uint256 rateAdjustedBalance = defaultAmount.mulDown(mockRate);
        uint256 rateAdjustedAmountGiven = defaultAmount.divDown(mockRate);

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.SwapParams({
                    kind: SwapKind.GIVEN_OUT,
                    amountGivenScaled18: defaultAmount,
                    balancesScaled18: [rateAdjustedBalance, defaultAmount].toMemoryArray(),
                    indexIn: 1,
                    indexOut: 0,
                    sender: address(router),
                    userData: bytes("")
                })
            )
        );

        vm.prank(bob);
        router.swapExactOut(
            address(pool),
            dai,
            wsteth,
            rateAdjustedAmountGiven,
            defaultAmount,
            type(uint256).max,
            false,
            bytes("")
        );
    }
}
