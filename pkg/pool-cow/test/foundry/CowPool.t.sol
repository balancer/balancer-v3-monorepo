// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IPoolInfo } from "@balancer-labs/v3-interfaces/contracts/pool-utils/IPoolInfo.sol";
import { ICowPool } from "@balancer-labs/v3-interfaces/contracts/pool-cow/ICowPool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CowPoolFactory } from "../../contracts/CowPoolFactory.sol";
import { CowPool } from "../../contracts/CowPool.sol";
import { BaseCowTest } from "./utils/BaseCowTest.sol";

contract CowPoolTest is BaseCowTest {
    address private _otherCowRouter;

    function setUp() public override {
        super.setUp();
        _otherCowRouter = address(deployCowPoolRouter(vault, 2e16, feeSweeper));
    }

    /********************************************************
                          Trusted Router
    ********************************************************/
    function testRefreshTrustedCowRouter() public {
        assertEq(
            CowPool(pool).getTrustedCowRouter(),
            address(cowRouter),
            "Wrong initial address for trusted cow router"
        );

        vm.prank(admin);
        CowPoolFactory(poolFactory).setTrustedCowRouter(_otherCowRouter);

        vm.expectEmit();
        emit ICowPool.CowTrustedRouterChanged(address(_otherCowRouter));
        CowPool(pool).refreshTrustedCowRouter();
        assertEq(
            CowPool(pool).getTrustedCowRouter(),
            address(_otherCowRouter),
            "Trusted cow router was not set properly"
        );
    }

    /********************************************************
                     Dynamic and Immutable Data
    ********************************************************/
    function testGetCowPoolDynamicData() public {
        ICowPool.CoWPoolDynamicData memory data = ICowPool(pool).getCowPoolDynamicData();

        (, uint256[] memory tokenRates) = vault.getPoolTokenRates(pool);
        IERC20[] memory tokens = IPoolInfo(pool).getTokens();
        uint256 totalSupply = IERC20(pool).totalSupply();

        assertTrue(data.isPoolInitialized, "Pool not initialized");
        assertFalse(data.isPoolPaused, "Pool paused");
        assertFalse(data.isPoolInRecoveryMode, "Pool in Recovery Mode");

        assertEq(data.totalSupply, totalSupply, "Total supply mismatch");
        assertEq(data.staticSwapFeePercentage, DEFAULT_SWAP_FEE, "Swap fee mismatch");

        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(data.balancesLiveScaled18[i], DEFAULT_AMOUNT, "Live balance mismatch");
            assertEq(data.tokenRates[i], tokenRates[i], "Token rate mismatch");
        }

        // Data should reflect the change in the static swap fee percentage.
        vault.manualSetStaticSwapFeePercentage(pool, 4e16);
        data = ICowPool(pool).getCowPoolDynamicData();
        assertEq(data.staticSwapFeePercentage, 4e16, "Swap fee mismatch");

        assertEq(data.trustedCowRouter, ICowPool(pool).getTrustedCowRouter(), "Trusted cow router mismatch");
    }

    function testGetCowPoolImmutableData() public view {
        ICowPool.CoWPoolImmutableData memory data = ICowPool(pool).getCowPoolImmutableData();
        (uint256[] memory scalingFactors, ) = vault.getPoolTokenRates(pool);
        IERC20[] memory tokens = IPoolInfo(pool).getTokens();

        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(address(data.tokens[i]), address(tokens[i]), "Token mismatch");
            assertEq(data.decimalScalingFactors[i], scalingFactors[i], "Decimal scaling factors mismatch");
            assertEq(data.normalizedWeights[i], uint256(50e16), "Weight mismatch");
        }
    }

    /********************************************************
                              Hooks
    ********************************************************/
    function testOnRegisterWrongPool() public {
        address wrongPool = address(1);
        // TokenConfig is not used by onRegister.
        TokenConfig[] memory tokenConfig;

        LiquidityManagement memory liquidityManagement;
        liquidityManagement.enableDonation = true;
        liquidityManagement.disableUnbalancedLiquidity = true;

        assertFalse(
            IHooks(pool).onRegister(poolFactory, wrongPool, tokenConfig, liquidityManagement),
            "onRegister succeeded with wrong pool"
        );
    }

    function testOnRegisterWrongFactory() public {
        address wrongFactory = address(1);
        // TokenConfig is not used by onRegister.
        TokenConfig[] memory tokenConfig;

        LiquidityManagement memory liquidityManagement;
        liquidityManagement.enableDonation = true;
        liquidityManagement.disableUnbalancedLiquidity = true;

        assertFalse(
            IHooks(pool).onRegister(wrongFactory, pool, tokenConfig, liquidityManagement),
            "onRegister succeeded with wrong factory"
        );
    }

    function testOnRegisterNoDonation() public {
        // TokenConfig is not used by onRegister.
        TokenConfig[] memory tokenConfig;

        LiquidityManagement memory liquidityManagement;
        liquidityManagement.enableDonation = false;
        liquidityManagement.disableUnbalancedLiquidity = true;

        assertFalse(
            IHooks(pool).onRegister(poolFactory, pool, tokenConfig, liquidityManagement),
            "onRegister succeeded with donations disabled"
        );
    }

    function testOnRegisterUnbalancedLiquidity() public {
        // TokenConfig is not used by onRegister.
        TokenConfig[] memory tokenConfig;

        LiquidityManagement memory liquidityManagement;
        liquidityManagement.enableDonation = true;
        liquidityManagement.disableUnbalancedLiquidity = false;

        assertFalse(
            IHooks(pool).onRegister(poolFactory, pool, tokenConfig, liquidityManagement),
            "onRegister succeeded with unbalanced liquidity"
        );
    }

    function testOnRegister() public {
        // TokenConfig is not used by onRegister.
        TokenConfig[] memory tokenConfig;

        LiquidityManagement memory liquidityManagement;
        liquidityManagement.enableDonation = true;
        liquidityManagement.disableUnbalancedLiquidity = true;

        assertTrue(IHooks(pool).onRegister(poolFactory, pool, tokenConfig, liquidityManagement), "onRegister failed");
    }

    function testGetHookFlags() public view {
        HookFlags memory hookFlags = IHooks(pool).getHookFlags();

        assertTrue(hookFlags.shouldCallBeforeSwap, "shouldCallBeforeSwap should be true");
        assertTrue(hookFlags.shouldCallBeforeAddLiquidity, "shouldCallBeforeAddLiquidity should be true");

        assertFalse(hookFlags.enableHookAdjustedAmounts, "enableHookAdjustedAmounts should be false");
        assertFalse(hookFlags.shouldCallBeforeInitialize, "shouldCallBeforeInitialize should be false");
        assertFalse(hookFlags.shouldCallAfterInitialize, "shouldCallAfterInitialize should be false");
        assertFalse(hookFlags.shouldCallComputeDynamicSwapFee, "shouldCallBeforeAddLiquidity should be false");
        assertFalse(hookFlags.shouldCallAfterSwap, "shouldCallAfterSwap should be false");
        assertFalse(hookFlags.shouldCallAfterAddLiquidity, "shouldCallAfterAddLiquidity should be false");
        assertFalse(hookFlags.shouldCallBeforeRemoveLiquidity, "shouldCallBeforeRemoveLiquidity should be false");
        assertFalse(hookFlags.shouldCallAfterRemoveLiquidity, "shouldCallAfterRemoveLiquidity should be false");
    }

    function testOnBeforeSwapWrongRouter() public {
        // CoW Pool's onBeforeSwap ignores the numeric inputs, so any number works.

        address wrongCowRouter = address(1);

        assertFalse(
            IHooks(pool).onBeforeSwap(
                PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: 1e18,
                    balancesScaled18: new uint256[](2),
                    indexIn: 0,
                    indexOut: 1,
                    router: wrongCowRouter,
                    userData: bytes("")
                }),
                pool
            ),
            "onBeforeSwap succeeded with wrong cow router"
        );
    }

    function testOnBeforeSwap() public {
        // CoW Pool's onBeforeSwap ignores the numeric inputs, so any number works.
        assertTrue(
            IHooks(pool).onBeforeSwap(
                PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: 1e18,
                    balancesScaled18: new uint256[](2),
                    indexIn: 0,
                    indexOut: 1,
                    router: address(cowRouter),
                    userData: bytes("")
                }),
                pool
            ),
            "onBeforeSwap failed with trusted cow router"
        );
    }

    function testOnBeforeAddLiquidityDonationWrongRouter() public {
        // CoW Pool's onBeforeAddLiquidity ignores the numeric inputs, so any number works.
        address wrongCowRouter = address(1);
        assertFalse(
            IHooks(pool).onBeforeAddLiquidity(
                wrongCowRouter,
                pool,
                AddLiquidityKind.DONATION,
                new uint256[](2),
                0,
                new uint256[](2),
                bytes("")
            ),
            "onBeforeAddLiquidity succeeded with Donation and wrong router"
        );
    }

    function testOnBeforeAddLiquidityNotDonationWrongRouter() public {
        // CoW Pool's onBeforeAddLiquidity ignores the numeric inputs, so any number works.
        address wrongCowRouter = address(1);
        assertTrue(
            IHooks(pool).onBeforeAddLiquidity(
                wrongCowRouter,
                pool,
                AddLiquidityKind.PROPORTIONAL,
                new uint256[](2),
                0,
                new uint256[](2),
                bytes("")
            ),
            "onBeforeAddLiquidity failed with Proportional add and wrong router"
        );
    }

    function testOnBeforeAddLiquidity() public {
        // CoW Pool's onBeforeAddLiquidity ignores the numeric inputs, so any number works.
        assertTrue(
            IHooks(pool).onBeforeAddLiquidity(
                address(cowRouter),
                pool,
                AddLiquidityKind.DONATION,
                new uint256[](2),
                0,
                new uint256[](2),
                bytes("")
            ),
            "onBeforeAddLiquidity failed with Donation and trusted cow router"
        );
    }
}
