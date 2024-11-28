// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { TokenConfig, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IPoolInfo } from "@balancer-labs/v3-interfaces/contracts/pool-utils/IPoolInfo.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    IStablePool,
    AmplificationState,
    StablePoolImmutableData,
    StablePoolDynamicData
} from "@balancer-labs/v3-interfaces/contracts/pool-stable/IStablePool.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import { BasePoolTest } from "@balancer-labs/v3-vault/test/foundry/utils/BasePoolTest.sol";
import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";

import { StablePoolContractsDeployer } from "./utils/StablePoolContractsDeployer.sol";
import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../contracts/StablePool.sol";

contract StablePoolTest is BasePoolTest, StablePoolContractsDeployer {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint256 constant DEFAULT_AMP_FACTOR = 200;
    uint256 constant TOKEN_AMOUNT = 1e3 * 1e18;

    function setUp() public virtual override {
        expectedAddLiquidityBptAmountOut = TOKEN_AMOUNT * 2;

        BasePoolTest.setUp();

        poolMinSwapFeePercentage = 1e12;
        poolMaxSwapFeePercentage = 10e16;
    }

    function createPool() internal override returns (address) {
        factory = deployStablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");

        TokenConfig[] memory tokenConfigs = new TokenConfig[](2);
        IERC20[] memory sortedTokens = InputHelpers.sortTokens(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );
        for (uint256 i = 0; i < sortedTokens.length; i++) {
            poolTokens.push(sortedTokens[i]);
            tokenConfigs[i].token = sortedTokens[i];

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
                    DEFAULT_AMP_FACTOR,
                    roleAccounts,
                    BASE_MIN_SWAP_FEE,
                    poolHooksContract,
                    false, // Do not enable donations
                    false, // Do not disable unbalanced add/remove liquidity
                    ZERO_BYTES32
                )
            )
        );

        // poolArgs is used to check pool deployment address with create2.
        poolArgs = abi.encode(
            StablePool.NewPoolParams({
                name: "ERC20 Pool",
                symbol: "ERC20POOL",
                amplificationParameter: DEFAULT_AMP_FACTOR,
                version: "Pool v1"
            }),
            vault
        );

        return stablePool;
    }

    function initPool() internal override {
        vm.prank(lp);
        bptAmountOut = router.initialize(
            pool,
            poolTokens,
            tokenAmounts,
            // Account for the precision loss
            expectedAddLiquidityBptAmountOut - BasePoolTest.DELTA,
            false,
            bytes("")
        );
    }

    function testGetBptRate() public {
        uint256 invariantBefore = StableMath.computeInvariant(
            DEFAULT_AMP_FACTOR * StableMath.AMP_PRECISION,
            [TOKEN_AMOUNT, TOKEN_AMOUNT].toMemoryArray()
        );
        uint256 invariantAfter = StableMath.computeInvariant(
            DEFAULT_AMP_FACTOR * StableMath.AMP_PRECISION,
            [2 * TOKEN_AMOUNT, TOKEN_AMOUNT].toMemoryArray()
        );

        uint256[] memory amountsIn = [TOKEN_AMOUNT, 0].toMemoryArray();
        _testGetBptRate(invariantBefore, invariantAfter, amountsIn);
    }

    function testGetAmplificationState() public {
        (AmplificationState memory ampState, uint256 precision) = IStablePool(pool).getAmplificationState();

        // Should be initialized to the default values.
        assertEq(ampState.startTime, block.timestamp, "Wrong initial amp update start time");
        assertEq(ampState.endTime, block.timestamp, "Wrong initial amp update end time");
        assertEq(ampState.startValue, DEFAULT_AMP_FACTOR * precision, "Wrong initial amp update start value");
        assertEq(ampState.endValue, DEFAULT_AMP_FACTOR * precision, "Wrong initial amp update end value");

        authorizer.grantRole(
            IAuthentication(pool).getActionId(StablePool.startAmplificationParameterUpdate.selector),
            admin
        );

        uint256 currentTime = block.timestamp;
        uint256 updateInterval = 5000 days;

        uint256 endTime = currentTime + updateInterval;
        uint256 newAmplificationParameter = DEFAULT_AMP_FACTOR * 2;

        vm.prank(admin);
        StablePool(pool).startAmplificationParameterUpdate(newAmplificationParameter, endTime);

        vm.warp(currentTime + updateInterval + 1);

        (ampState, precision) = IStablePool(pool).getAmplificationState();

        // Should be initialized to the default values.
        assertEq(ampState.startTime, currentTime, "Wrong amp update start time");
        assertEq(ampState.endTime, endTime, "Wrong amp update end time");
        assertEq(ampState.startValue, DEFAULT_AMP_FACTOR * precision, "Wrong amp update start value");
        assertEq(ampState.endValue, newAmplificationParameter * precision, "Wrong amp update end value");
    }

    function testGetStablePoolImmutableData() public view {
        StablePoolImmutableData memory data = IStablePool(pool).getStablePoolImmutableData();
        (, , uint256 precision) = IStablePool(pool).getAmplificationParameter();
        (uint256[] memory scalingFactors, ) = vault.getPoolTokenRates(pool);
        IERC20[] memory tokens = IPoolInfo(pool).getTokens();

        assertEq(data.amplificationParameterPrecision, precision, "Wrong amplification parameter precision");
        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(address(data.tokens[i]), address(tokens[i]), "Token mismatch");
            assertEq(data.decimalScalingFactors[i], scalingFactors[i], "Decimal scaling factors mismatch");
        }
    }

    function testGetStablePoolDynamicData() public view {
        (AmplificationState memory ampState, uint256 precision) = IStablePool(pool).getAmplificationState();
        StablePoolDynamicData memory data = IStablePool(pool).getStablePoolDynamicData();
        (, uint256[] memory tokenRates) = vault.getPoolTokenRates(pool);
        IERC20[] memory tokens = IPoolInfo(pool).getTokens();
        uint256 totalSupply = IERC20(pool).totalSupply();
        uint256 bptRate = vault.getBptRate(pool);

        assertTrue(data.isPoolInitialized, "Pool not initialized");
        assertFalse(data.isPoolPaused, "Pool paused");
        assertFalse(data.isPoolInRecoveryMode, "Pool in Recovery Mode");

        assertEq(data.amplificationParameter, DEFAULT_AMP_FACTOR * precision, "Amp factor mismatch");
        assertEq(data.startValue, ampState.startValue, "Start value mismatch");
        assertEq(data.endValue, ampState.endValue, "End value mismatch");
        assertEq(data.startTime, ampState.startTime, "Start time mismatch");
        assertEq(data.endTime, ampState.endTime, "End time mismatch");
        assertEq(data.bptRate, bptRate, "BPT rate mismatch");
        assertEq(data.totalSupply, totalSupply, "Total supply mismatch");

        assertEq(data.staticSwapFeePercentage, BASE_MIN_SWAP_FEE, "Swap fee mismatch");

        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(data.balancesLiveScaled18[i], defaultAmount, "Live balance mismatch");
            assertEq(data.tokenRates[i], tokenRates[i], "Token rate mismatch");
        }
    }
}
