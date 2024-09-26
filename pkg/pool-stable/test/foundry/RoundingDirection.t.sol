// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig, PoolRoleAccounts, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

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
import {
    TokenConfig,
    TokenInfo,
    TokenType,
    PoolRoleAccounts,
    LiquidityManagement,
    PoolConfig,
    HooksConfig,
    Rounding,
    SwapKind,
    PoolData,
    PoolSwapParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

contract RoundingDirectionStablePoolTest is BasePoolTest {
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

    function testFuzzEdgeTokenAmount(uint tokenAmount, uint dustAmount) public {
        tokenAmount = bound(tokenAmount, 1e10 ether, 1e12 ether);
        dustAmount = bound(dustAmount, 1, 1e3);
        uint[] memory currentBalances = [tokenAmount, dustAmount].toMemoryArray();
        bool first = false;
        bool second = false;
        try StablePool(pool).computeInvariant(currentBalances, Rounding.ROUND_UP) returns (uint256 invariant) {
            first = true;
        } catch {}
        if (!first) {
            currentBalances = [tokenAmount, dustAmount + 1].toMemoryArray();
            try StablePool(pool).computeInvariant(currentBalances, Rounding.ROUND_DOWN) returns (uint256 invariant) {
                second = true;
            } catch {}
        }

        vm.assertTrue(!second);
        vm.assertTrue(first);
    }

    function testEdgeCaseLiquidity() public {
        // assume a perfect case with no fee;
        uint initialTotalSupply = 1 ether;
        uint tokenAmount = 1e6;
        uint inputAmount = 1e6;
        uint dustAmount = 2;
        uint[] memory currentBalances = [tokenAmount, dustAmount].toMemoryArray();
        uint previousInvariant = StablePool(pool).computeInvariant(currentBalances, Rounding.ROUND_UP);
        uint postInvariant = StablePool(pool).computeInvariant(
            [tokenAmount + inputAmount, dustAmount].toMemoryArray(),
            Rounding.ROUND_DOWN
        );
        uint lpAmountAfterMint = (initialTotalSupply * postInvariant) / previousInvariant;
        uint mintedLpAmount = lpAmountAfterMint - initialTotalSupply;
        uint previousInvariant2 = StablePool(pool).computeInvariant(
            [tokenAmount + inputAmount, dustAmount - 1].toMemoryArray(),
            Rounding.ROUND_UP
        );
        uint postInvariant2 = StablePool(pool).computeInvariant(
            [tokenAmount, dustAmount - 1].toMemoryArray(),
            Rounding.ROUND_DOWN
        );
        uint lpAmountAfterBurn = (lpAmountAfterMint * postInvariant2) / previousInvariant2;
        uint burnedLpAmount = lpAmountAfterMint - lpAmountAfterBurn;
        vm.assertGt(mintedLpAmount, burnedLpAmount);
    }

    function testMockPoolBalanceWithRate() public {
        uint tokenAmount = 1e6;
        uint dustAmount = 1;
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
        vm.startPrank(lp);
        uint256[] memory exactAmountsIn = [tokenAmount, uint(0)].toMemoryArray();
        uint mintLp = router.addLiquidityUnbalanced(pool, exactAmountsIn, 0, false, "");
        uint lpBurned = router.removeLiquiditySingleTokenExactOut(pool, 1e50, usdc, tokenAmount, false, "");
        vm.assertGt(mintLp, lpBurned);
        assertEq(IERC20(pool).balanceOf(lp), 0, "LP still has shares");
    }

    function testMockPoolBalanceWithRateExactIn() public {
        uint tokenAmount = 1e6;
        uint dustAmount = 1;
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

        BasePoolTest.Balances memory balancesBefore = getBalances(lp);

        vm.startPrank(lp);
        uint256[] memory exactAmountsIn = [tokenAmount, uint(0)].toMemoryArray();
        uint mintLp = router.addLiquidityUnbalanced(pool, exactAmountsIn, 0, false, "");
        uint lpBurned = router.removeLiquiditySingleTokenExactIn(pool, IERC20(pool).balanceOf(lp), usdc, 1, false, "");

        BasePoolTest.Balances memory balancesAfter = getBalances(lp);

        assertEq(IERC20(pool).balanceOf(lp), 0, "LP still has shares");
    }

    function testMockPoolBalanceWithRateFullExit() public {
        uint tokenAmount = 1e6;
        uint dustAmount = 1;
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

        router.removeLiquidityProportional(pool, 0, [uint256(0), uint256(0)].toMemoryArray(), false, "");

        (, , , uint256[] memory lastBalancesLiveScaled18) = vault.getPoolTokenInfo(pool);

        uint256 usdcBalanceBefore = IERC20(usdc).balanceOf(lp);
        uint256 wstETHBalanceBefore = IERC20(wsteth).balanceOf(lp);
        uint256 invariantBefore = IBasePool(pool).computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_DOWN);

        vm.startPrank(alice);
        uint256[] memory exactAmountsIn = [tokenAmount, uint(0)].toMemoryArray();
        uint mintLp = router.addLiquidityUnbalanced(pool, exactAmountsIn, 0, false, "");

        console.log("minted LP: ", mintLp);

        (, , , lastBalancesLiveScaled18) = vault.getPoolTokenInfo(pool);

        uint lpBurned = router.removeLiquiditySingleTokenExactOut(pool, 1e50, usdc, tokenAmount, false, "");
        assertGt(mintLp, lpBurned, "BPT test");
        uint256 invariantMid = IBasePool(pool).computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_DOWN);
        router.removeLiquidityProportional(
            pool,
            IERC20(pool).balanceOf(alice),
            [uint256(0), uint256(0)].toMemoryArray(),
            false,
            ""
        );

        (, , , lastBalancesLiveScaled18) = vault.getPoolTokenInfo(pool);
        uint256 usdcBalanceAfter = IERC20(usdc).balanceOf(lp);
        uint256 wstETHBalanceAfter = IERC20(wsteth).balanceOf(lp);
        uint256 invariantAfter = IBasePool(pool).computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_DOWN);

        console.log("USDC balance before: ", usdcBalanceBefore);
        console.log("USDC balance after: ", usdcBalanceAfter);

        console.log("wsteth balance before: ", wstETHBalanceBefore);
        console.log("wsteth balance after: ", wstETHBalanceAfter);

        console.log("invariant before: ", invariantBefore);
        console.log("invariant mid: ", invariantMid);
        console.log("invariant after: ", invariantAfter);

        assertEq(IERC20(pool).balanceOf(alice), 0, "LP still has shares");
        assertGe(invariantAfter, invariantBefore, "Invariant decreased");
    }

    function testMockPoolBalanceWithRate2() public {
        uint tokenAmount = 1e6;
        uint dustAmount = 1;
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(usdc);
        tokens[1] = IERC20(wsteth);
        vault.manualSetPoolTokensAndBalances(
            pool,
            tokens,
            [tokenAmount, 1].toMemoryArray(),
            [tokenAmount, 1].toMemoryArray()
        );
        rateProviderWstEth.mockRate(1.5e18);
        vm.startPrank(alice);
        uint256[] memory exactAmountsIn = [tokenAmount * 3, dustAmount * 2].toMemoryArray();

        (, , , uint256[] memory lastBalancesLiveScaled18) = vault.getPoolTokenInfo(pool);
        uint256 usdcBalanceBefore = IERC20(usdc).balanceOf(alice);
        uint256 wstETHBalanceBefore = IERC20(wsteth).balanceOf(alice);
        uint256 invariantBefore = IBasePool(pool).computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_DOWN);

        uint mintLp = router.addLiquidityUnbalanced(pool, exactAmountsIn, 0, false, "");

        console2.log("bptrate:", StablePool(pool).getRate());
        uint[] memory minAmountsOut = [uint(1), uint(1)].toMemoryArray();
        uint[] memory amountsOut = router.removeLiquidityProportional(pool, mintLp, minAmountsOut, false, "");

        (, , , lastBalancesLiveScaled18) = vault.getPoolTokenInfo(pool);
        uint256 usdcBalanceAfter = IERC20(usdc).balanceOf(alice);
        uint256 wstETHBalanceAfter = IERC20(wsteth).balanceOf(alice);
        uint256 invariantAfter = IBasePool(pool).computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_DOWN);

        console.log("usdc before: %d", usdcBalanceBefore);
        console.log("wstETH before: %d", wstETHBalanceBefore);
        console.log("invariant before: %d", invariantBefore);

        console.log("usdc after: %d", usdcBalanceAfter);
        console.log("wstETH after: %d", wstETHBalanceAfter);
        console.log("invariant after: %d", invariantAfter);

        assertGe(invariantAfter, invariantBefore, "Invariant decreased");
        // In this test case, users get exact same wstETH back and some USDC profit.
    }

    function testComputeBalance(
        uint256 currentAmp,
        uint256 balance0,
        uint256 balance1,
        uint256 balance2,
        uint256 invariantRatio
    ) public {
        currentAmp = bound(currentAmp, 100, 10000);
        balance0 = bound(balance0, 1000e18, 1_000_000e18);
        balance1 = bound(balance1, 1000e18, 1_000_000e18);
        balance2 = bound(balance2, 1000e18, 1_000_000e18);
        invariantRatio = bound(invariantRatio, 60e16, 300e16);
        uint256 tokenInIndex = bound(balance0 + balance1 + balance2, 0, 2);

        uint256[] memory balancesLiveScaled18 = new uint256[](3);
        balancesLiveScaled18[0] = balance0;
        balancesLiveScaled18[1] = balance1;
        balancesLiveScaled18[2] = balance2;

        try this.computeInvariant(currentAmp, balancesLiveScaled18, Rounding.ROUND_DOWN) returns (
            uint256 invariant
        ) {} catch {
            vm.assume(false);
        }

        uint256 balanceRoundDown = StableMath.computeBalance(
            currentAmp,
            balancesLiveScaled18,
            computeInvariant(currentAmp, balancesLiveScaled18, Rounding.ROUND_DOWN).mulDown(invariantRatio),
            tokenInIndex
        );

        uint256 balanceRoundUp = StableMath.computeBalance(
            currentAmp,
            balancesLiveScaled18,
            computeInvariant(currentAmp, balancesLiveScaled18, Rounding.ROUND_UP).mulUp(invariantRatio),
            tokenInIndex
        );

        assertGe(balanceRoundDown, balanceRoundUp, "Incorrect assumption");
    }

    function computeInvariant(
        uint256 currentAmp,
        uint256[] memory balancesLiveScaled18,
        Rounding rounding
    ) public view returns (uint256) {
        uint256 invariant = StableMath.computeInvariant(currentAmp, balancesLiveScaled18);
        if (invariant > 0) {
            invariant = rounding == Rounding.ROUND_DOWN ? invariant : invariant + 1;
        }

        return invariant;
    }

    fallback() external {
        console.log("wat");
    }
}
