// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { BasePoolTest } from "@balancer-labs/v3-vault/test/foundry/utils/BasePoolTest.sol";

import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../contracts/StablePool.sol";
import { RateProviderMock } from "../../../vault/contracts/test/RateProviderMock.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

contract RoundingDirectionStablePoolEdgeCasesTest is BasePoolTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 constant TOKEN_AMOUNT = 1e3 ether;
    RateProviderMock rateProviderWstEth;

    function setUp() public virtual override {
        expectedAddLiquidityBptAmountOut = TOKEN_AMOUNT * 2;

        BasePoolTest.setUp();

        poolMinSwapFeePercentage = 1e12;
        poolMaxSwapFeePercentage = 10e16;
    }

    function createPool() internal override returns (address) {
        factory = new StablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");

        TokenConfig[] memory tokenConfigs = new TokenConfig[](2);
        IERC20[] memory sortedTokens = InputHelpers.sortTokens(
            [address(usdc), address(wsteth)].toMemoryArray().asIERC20()
        );
        for (uint256 i = 0; i < sortedTokens.length; i++) {
            poolTokens.push(sortedTokens[i]);
            tokenConfigs[i].token = sortedTokens[i];
            if (address(sortedTokens[i]) == address(wsteth)) {
                rateProviderWstEth = new RateProviderMock();
                rateProviderWstEth.mockRate(1e18);
                tokenConfigs[i].rateProvider = IRateProvider(address(rateProviderWstEth));
                tokenConfigs[i].tokenType = TokenType.WITH_RATE;
            }
            tokenAmounts.push(TOKEN_AMOUNT);
        }

        PoolRoleAccounts memory roleAccounts;
        // Allow pools created by `factory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        address stablePool = address(
            StablePool(
                StablePoolFactory(address(factory)).create(
                    "ERC20 Pool",
                    "ERC20POOL",
                    tokenConfigs,
                    // DEFAULT_AMP_FACTOR,
                    2000,
                    roleAccounts,
                    BASE_MIN_SWAP_FEE,
                    poolHooksContract,
                    false, // Do not enable donations
                    false, // Do not disable unbalanced add/remove liquidity
                    ZERO_BYTES32
                )
            )
        );
        return stablePool;
    }

    function initPool() internal override {
        vm.prank(lp);
        bptAmountOut = router.initialize(
            pool,
            poolTokens,
            tokenAmounts,
            expectedAddLiquidityBptAmountOut - BasePoolTest.DELTA,
            false,
            bytes("")
        );
    }

    function testMockPoolBalanceWithEdgeCase() public {
        setSwapFeePercentage(0);

        uint256 tokenAmount = 1e6;
        uint256 dustAmount = 1;
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(usdc);
        tokens[1] = IERC20(wsteth);
        vault.manualSetPoolTokensAndBalances(
            pool,
            tokens,
            [tokenAmount, dustAmount].toMemoryArray(),
            [tokenAmount, dustAmount].toMemoryArray()
        );
        rateProviderWstEth.mockRate(1.001e18);

        vm.startPrank(alice);

        router.removeLiquidityProportional(pool, 0, [uint256(0), uint256(0)].toMemoryArray(), false, "");

        uint256[] memory exactAmountsIn = [tokenAmount, uint256(0)].toMemoryArray();

        router.addLiquidityUnbalanced(pool, exactAmountsIn, 0, false, "");

        // This will actually revert as base pool math will attempt to compute an invariant with 0 balances.
        vm.expectRevert(stdError.divisionError);
        router.removeLiquiditySingleTokenExactOut(pool, 1e50, usdc, tokenAmount, false, "");
    }

    function testMockPoolBalanceWithEdgeCaseAddUnbalanced() public {
        setSwapFeePercentage(0);
        uint256 tokenAmount = 1e6;
        uint256 dustAmount = 1;
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(usdc);
        tokens[1] = IERC20(wsteth);
        vault.manualSetPoolTokensAndBalances(
            pool,
            tokens,
            [tokenAmount, dustAmount].toMemoryArray(),
            [tokenAmount, dustAmount].toMemoryArray()
        );
        rateProviderWstEth.mockRate(1.5e18);
        uint256 previousTotalSupply = StablePool(pool).totalSupply();
        uint256[] memory exactAmountsIn = [tokenAmount * 2 , dustAmount * 2].toMemoryArray();
        uint256 mintLp;
        vm.prank(alice);
        mintLp = router.addLiquidityUnbalanced(pool, exactAmountsIn, 0, false, "");
        // This is only true when trading fee is 0
        vm.assertLt(mintLp, previousTotalSupply * 2);
    }

    function testComputeInvariantRatio(
        uint256 currentAmp,
        uint256[3] memory currentBalances,
        uint256[3] memory amountsIn
    ) public view {
        currentAmp = bound(currentAmp, 100, 1000);
        currentBalances[0] = bound(currentBalances[0], 1000e18, 1_000_000e18);
        currentBalances[1] = bound(currentBalances[1], 1000e18, 1_000_000e18);
        currentBalances[2] = bound(currentBalances[2], 1000e18, 1_000_000e18);
        amountsIn[0] = bound(amountsIn[0], 1e18, 10_000e18);
        amountsIn[1] = bound(amountsIn[1], 1e18, 10_000e18);
        amountsIn[2] = bound(amountsIn[2], 1e18, 10_000e18);

        uint256[] memory newBalances = new uint256[](3);
        newBalances[0] = currentBalances[0] + amountsIn[0];
        newBalances[1] = currentBalances[0] + amountsIn[1];
        newBalances[2] = currentBalances[0] + amountsIn[2];

        uint256[] memory newBalancesRoundDown = new uint256[](3);
        newBalancesRoundDown[0] = newBalances[0] - 1;
        newBalancesRoundDown[1] = newBalances[1] - 1;
        newBalancesRoundDown[2] = newBalances[2] - 1;

        try this.computeInvariant(currentAmp, currentBalances.toMemoryArray(), Rounding.ROUND_DOWN) returns (
            uint256
        ) {} catch {
            vm.assume(false);
        }

        try this.computeInvariant(currentAmp, newBalances, Rounding.ROUND_UP) returns (
            uint256
        ) {} catch {
            vm.assume(false);
        }

        try this.computeInvariant(currentAmp, newBalancesRoundDown, Rounding.ROUND_UP) returns (
            uint256
        ) {} catch {
            vm.assume(false);
        }

        uint256 currentInvariant = computeInvariant(currentAmp, currentBalances.toMemoryArray(), Rounding.ROUND_DOWN);
        // Round down to make `taxableAmount` larger below.
        uint256 invariantRatioRegular = computeInvariant(currentAmp, newBalances, Rounding.ROUND_DOWN).divDown(currentInvariant);


        uint256 currentInvariantUp = computeInvariant(currentAmp, currentBalances.toMemoryArray(), Rounding.ROUND_UP);
        // Round down to make `taxableAmount` larger below.
        uint256 invariantRatioDown = computeInvariant(currentAmp, newBalancesRoundDown, Rounding.ROUND_DOWN).divDown(currentInvariantUp);

        assertLe(invariantRatioDown, invariantRatioRegular, "Incorrect assumption");
    }

    function computeInvariant(
        uint256 currentAmp,
        uint256[] memory balancesLiveScaled18,
        Rounding rounding
    ) public pure returns (uint256) {
        uint256 invariant = StableMath.computeInvariant(currentAmp, balancesLiveScaled18);
        if (invariant > 0) {
            invariant = rounding == Rounding.ROUND_DOWN ? invariant : invariant + 1;
        }

        return invariant;
    }
}