// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
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

    // Track the indices for the local dai/wsteth pool.
    uint256 internal daiIdx;
    uint256 internal wstethIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        (daiIdx, wstethIdx) = getSortedIndexes(address(dai), address(wsteth));
    }

    function createPool() internal override returns (address) {
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProvider = new RateProviderMock();
        // Must match the array passed in, not the sorted index, since buildTokenConfig will do the sorting.
        rateProviders[0] = rateProvider;
        rateProvider.mockRate(mockRate);

        return
            address(
                new PoolMock(
                    IVault(address(vault)),
                    "ERC20 Pool",
                    "ERC20POOL",
                    vault.buildTokenConfig([address(wsteth), address(dai)].toMemoryArray().asIERC20(), rateProviders),
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
        (, , , , IRateProvider[] memory rateProviders) = vault.getPoolTokenInfo(address(pool));

        assertEq(address(rateProviders[wstethIdx]), address(rateProvider), "Wrong rate provider");
        assertEq(address(rateProviders[daiIdx]), address(0), "Rate provider should be 0");
    }

    function testSwapSingleTokenExactIWithRate() public {
        uint256 rateAdjustedLimit = defaultAmount.divDown(mockRate);
        uint256 rateAdjustedAmount = defaultAmount.mulDown(mockRate);

        uint256[] memory expectedBalances = new uint256[](2);
        expectedBalances[wstethIdx] = rateAdjustedAmount;
        expectedBalances[daiIdx] = defaultAmount;

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: defaultAmount,
                    balancesScaled18: expectedBalances,
                    indexIn: daiIdx,
                    indexOut: wstethIdx,
                    sender: address(router),
                    userData: bytes("")
                })
            )
        );

        vm.prank(bob);
        router.swapSingleTokenExactIn(
            address(pool),
            dai,
            wsteth,
            defaultAmount,
            rateAdjustedLimit,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    function testSwapSingleTokenExactOutWithRate() public {
        uint256 rateAdjustedBalance = defaultAmount.mulDown(mockRate);
        uint256 rateAdjustedAmountGiven = defaultAmount.divDown(mockRate);

        uint256[] memory expectedBalances = new uint256[](2);
        expectedBalances[wstethIdx] = rateAdjustedBalance;
        expectedBalances[daiIdx] = defaultAmount;

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.PoolSwapParams({
                    kind: SwapKind.EXACT_OUT,
                    amountGivenScaled18: defaultAmount,
                    balancesScaled18: expectedBalances,
                    indexIn: daiIdx,
                    indexOut: wstethIdx,
                    sender: address(router),
                    userData: bytes("")
                })
            )
        );

        vm.prank(bob);
        router.swapSingleTokenExactOut(
            address(pool),
            dai,
            wsteth,
            rateAdjustedAmountGiven,
            defaultAmount,
            MAX_UINT256,
            false,
            bytes("")
        );
    }
}
