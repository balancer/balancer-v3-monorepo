// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { TokenInfo, SwapKind, PoolSwapParams } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

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

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "ERC20 Pool";
        string memory symbol = "ERC20POOL";

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProvider = deployRateProviderMock();
        // Must match the array passed in, not the sorted index, since buildTokenConfig will do the sorting.
        rateProviders[0] = rateProvider;
        rateProvider.mockRate(mockRate);

        newPool = address(deployPoolMock(IVault(address(vault)), name, symbol));

        factoryMock.registerTestPool(
            newPool,
            vault.buildTokenConfig([address(wsteth), address(dai)].toMemoryArray().asIERC20(), rateProviders),
            poolHooksContract,
            lp
        );

        poolArgs = abi.encode(vault, name, symbol);
    }

    function testInitializePoolWithRate() public view {
        // Mock pool invariant is linear (just a sum of all balances).
        assertEq(
            PoolMock(pool).balanceOf(lp),
            defaultAmount + defaultAmount.mulDown(mockRate) - POOL_MINIMUM_TOTAL_SUPPLY,
            "Invalid amount of BPT"
        );
    }

    function testInitialRateProviderState() public view {
        (, TokenInfo[] memory tokenInfo, , ) = vault.getPoolTokenInfo(pool);

        assertEq(address(tokenInfo[wstethIdx].rateProvider), address(rateProvider), "Wrong rate provider");
        assertEq(address(tokenInfo[daiIdx].rateProvider), address(0), "Rate provider should be 0");
    }

    function testSwapSingleTokenExactIWithRate() public {
        uint256 rateAdjustedLimit = defaultAmount.divDown(mockRate);
        uint256 rateAdjustedAmount = defaultAmount.mulDown(mockRate);

        uint256[] memory expectedBalances = new uint256[](2);
        expectedBalances[wstethIdx] = rateAdjustedAmount;
        expectedBalances[daiIdx] = defaultAmount;

        vm.expectCall(
            pool,
            abi.encodeCall(
                IBasePool.onSwap,
                PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: defaultAmount,
                    balancesScaled18: expectedBalances,
                    indexIn: daiIdx,
                    indexOut: wstethIdx,
                    router: address(router),
                    userData: bytes("")
                })
            )
        );

        vm.prank(bob);
        router.swapSingleTokenExactIn(
            pool,
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
            pool,
            abi.encodeCall(
                IBasePool.onSwap,
                PoolSwapParams({
                    kind: SwapKind.EXACT_OUT,
                    amountGivenScaled18: defaultAmount,
                    balancesScaled18: expectedBalances,
                    indexIn: daiIdx,
                    indexOut: wstethIdx,
                    router: address(router),
                    userData: bytes("")
                })
            )
        );

        vm.prank(bob);
        router.swapSingleTokenExactOut(
            pool,
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
