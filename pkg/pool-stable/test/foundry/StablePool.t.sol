// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { TokenConfig, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IPoolInfo } from "@balancer-labs/v3-interfaces/contracts/pool-utils/IPoolInfo.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
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

    string constant POOL_VERSION = "Pool v1";
    uint256 constant DEFAULT_AMP_FACTOR = 200;
    uint256 constant TOKEN_AMOUNT = 1e3 * 1e18;

    function setUp() public virtual override {
        expectedAddLiquidityBptAmountOut = TOKEN_AMOUNT * 2;

        BasePoolTest.setUp();

        poolMinSwapFeePercentage = 1e12;
        poolMaxSwapFeePercentage = 10e16;
    }

    function createPoolFactory() internal override returns (address) {
        return address(deployStablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", POOL_VERSION));
    }

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "ERC20 Pool";
        string memory symbol = "ERC20POOL";

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
        roleAccounts.swapFeeManager = alice;

        // Allow pools created by `factory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(poolFactory);

        newPool = StablePoolFactory(poolFactory).create(
            name,
            symbol,
            tokenConfigs,
            DEFAULT_AMP_FACTOR,
            roleAccounts,
            BASE_MIN_SWAP_FEE,
            poolHooksContract,
            false, // Do not enable donations
            false, // Do not disable unbalanced add/remove liquidity
            ZERO_BYTES32
        );

        // poolArgs is used to check pool deployment address with create2.
        poolArgs = abi.encode(
            StablePool.NewPoolParams({
                name: name,
                symbol: symbol,
                amplificationParameter: DEFAULT_AMP_FACTOR,
                version: POOL_VERSION
            }),
            vault
        );
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

    function testAmplificationUpdateBySwapFeeManager() public {
        // Ensure the swap manager was set for the pool.
        assertEq(vault.getPoolRoleAccounts(pool).swapFeeManager, alice, "Wrong swap fee manager");

        // Ensure the swap manager doesn't have permission through governance.
        assertFalse(
            authorizer.hasRole(
                IAuthentication(pool).getActionId(StablePool.startAmplificationParameterUpdate.selector),
                alice
            ),
            "Has governance-granted start permission"
        );
        assertFalse(
            authorizer.hasRole(
                IAuthentication(pool).getActionId(StablePool.stopAmplificationParameterUpdate.selector),
                alice
            ),
            "Has governance-granted stop permission"
        );

        // Ensure the swap manager account can start/stop anyway.
        uint256 currentTime = block.timestamp;
        uint256 updateInterval = 5000 days;

        uint256 endTime = currentTime + updateInterval;
        uint256 newAmplificationParameter = DEFAULT_AMP_FACTOR * 2;

        vm.startPrank(alice);
        IStablePool(pool).startAmplificationParameterUpdate(newAmplificationParameter, endTime);

        (, bool isUpdating, ) = IStablePool(pool).getAmplificationParameter();
        assertTrue(isUpdating, "Amplification update not started");

        IStablePool(pool).stopAmplificationParameterUpdate();
        vm.stopPrank();

        (, isUpdating, ) = IStablePool(pool).getAmplificationParameter();
        assertFalse(isUpdating, "Amplification update not stopped");

        // Grant to Bob via governance.
        authorizer.grantRole(
            IAuthentication(pool).getActionId(StablePool.startAmplificationParameterUpdate.selector),
            bob
        );

        vm.startPrank(bob);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        IStablePool(pool).startAmplificationParameterUpdate(newAmplificationParameter, endTime);
    }

    function testAmplificationUpdateByGovernance() public {
        PoolRoleAccounts memory poolRoleAccounts = PoolRoleAccounts({
            pauseManager: address(0x00),
            swapFeeManager: address(0x00),
            poolCreator: address(0x00)
        });
        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IVaultExtension.getPoolRoleAccounts.selector, pool),
            abi.encode(poolRoleAccounts)
        );

        assertFalse(
            authorizer.hasRole(
                IAuthentication(pool).getActionId(StablePool.startAmplificationParameterUpdate.selector),
                bob
            ),
            "Has governance-granted start permission"
        );
        assertFalse(
            authorizer.hasRole(
                IAuthentication(pool).getActionId(StablePool.stopAmplificationParameterUpdate.selector),
                bob
            ),
            "Has governance-granted stop permission"
        );

        // Ensure the swap manager account can start/stop anyway.
        uint256 currentTime = block.timestamp;
        uint256 updateInterval = 5000 days;

        uint256 endTime = currentTime + updateInterval;
        uint256 newAmplificationParameter = DEFAULT_AMP_FACTOR * 2;

        // Test that the swap manager can't start/stop the update.
        vm.prank(bob);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        IStablePool(pool).startAmplificationParameterUpdate(newAmplificationParameter, endTime);

        // Grant to Bob via governance.
        authorizer.grantRole(
            IAuthentication(pool).getActionId(StablePool.startAmplificationParameterUpdate.selector),
            bob
        );
        authorizer.grantRole(
            IAuthentication(pool).getActionId(StablePool.stopAmplificationParameterUpdate.selector),
            bob
        );

        vm.startPrank(bob);
        IStablePool(pool).startAmplificationParameterUpdate(newAmplificationParameter, endTime);

        (, bool isUpdating, ) = IStablePool(pool).getAmplificationParameter();
        assertTrue(isUpdating, "Amplification update not started");

        IStablePool(pool).stopAmplificationParameterUpdate();
        vm.stopPrank();

        (, isUpdating, ) = IStablePool(pool).getAmplificationParameter();
        assertFalse(isUpdating, "Amplification update not stopped");
    }

    function testGetAmplificationState() public {
        (AmplificationState memory ampState, uint256 precision) = IStablePool(pool).getAmplificationState();

        // Should be initialized to the default values.
        assertEq(ampState.startTime, block.timestamp, "Wrong initial amp update start time");
        assertEq(ampState.endTime, block.timestamp, "Wrong initial amp update end time");
        assertEq(ampState.startValue, DEFAULT_AMP_FACTOR * precision, "Wrong initial amp update start value");
        assertEq(ampState.endValue, DEFAULT_AMP_FACTOR * precision, "Wrong initial amp update end value");

        uint256 currentTime = block.timestamp;
        uint256 updateInterval = 5000 days;

        uint256 endTime = currentTime + updateInterval;
        uint256 newAmplificationParameter = DEFAULT_AMP_FACTOR * 2;

        vm.prank(alice);
        IStablePool(pool).startAmplificationParameterUpdate(newAmplificationParameter, endTime);

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
            assertEq(data.balancesLiveScaled18[i], DEFAULT_AMOUNT, "Live balance mismatch");
            assertEq(data.tokenRates[i], tokenRates[i], "Token rate mismatch");
        }
    }
}
