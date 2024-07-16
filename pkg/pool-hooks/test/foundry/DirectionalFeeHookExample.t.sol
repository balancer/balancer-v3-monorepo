// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import {
    HooksConfig,
    LiquidityManagement,
    PoolConfig,
    PoolRoleAccounts,
    SwapKind,
    TokenConfig
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";

import { StablePoolFactory } from "@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { DirectionalFeeHookExample } from "../../contracts/DirectionalFeeHookExample.sol";

contract DirectionalHookExampleTest is BaseVaultTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    StablePoolFactory internal stablePoolFactory;

    uint256 internal constant DEFAULT_AMP_FACTOR = 200;
    // 10% swap fee
    uint256 internal constant SWAP_FEE_PERCENTAGE = 0.1e18;

    function setUp() public override {
        super.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function createHook() internal override returns (address) {
        // Create the factory here, because it needs to be deployed after the vault, but before the hook contract.
        stablePoolFactory = new StablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
        // lp will be the owner of the hook. Only LP is able to set hook fee percentages.
        vm.prank(lp);
        address directionalFeeHook = address(
            new DirectionalFeeHookExample(IVault(address(vault)), address(stablePoolFactory))
        );
        vm.label(directionalFeeHook, "Directional Fee Hook");
        return directionalFeeHook;
    }

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        PoolRoleAccounts memory roleAccounts;

        address newPool = address(
            stablePoolFactory.create(
                "Stable Pool Test",
                "STABLE-TEST",
                vault.buildTokenConfig(tokens.asIERC20()),
                DEFAULT_AMP_FACTOR,
                roleAccounts,
                MIN_SWAP_FEE,
                poolHooksContract,
                false, // Does not allow donations
                false, // Do not disable unbalanced add/remove liquidity
                ZERO_BYTES32
            )
        );
        vm.label(newPool, label);

        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), admin);
        vm.prank(admin);
        vault.setStaticSwapFeePercentage(newPool, SWAP_FEE_PERCENTAGE);

        return newPool;
    }

    function testRegistryWithWrongFactory() public {
        address directionalFeePool = _createPoolToRegister();
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        // Registration fails because factory is not allowed to register hook
        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.HookRegistrationFailed.selector,
                poolHooksContract,
                directionalFeePool,
                address(factoryMock)
            )
        );
        _registerPoolWithHook(directionalFeePool, tokenConfig);
    }

    function testSuccessfulRegistry() public view {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);

        assertEq(hooksConfig.hooksContract, poolHooksContract, "pool's hooks contract is wrong");
        assertTrue(hooksConfig.shouldCallComputeDynamicSwapFee, "hook's shouldCallComputeDynamicSwapFee is wrong");
    }

    function testSwapBalancingPoolFee() public {
        // Make a first swap to unbalance the pool meaningfully (Much more USDC than DAI)
        vm.prank(bob);
        router.swapSingleTokenExactIn(pool, usdc, dai, poolInitAmount / 2, 0, MAX_UINT256, false, bytes(""));

        uint256 daiExactAmountIn = poolInitAmount / 10;

        BaseVaultTest.Balances memory balancesBefore = getBalances(lp);

        // Calculate the expected amount out (amount out without fees)
        uint256 poolInvariant = StableMath.computeInvariant(
            DEFAULT_AMP_FACTOR * StableMath.AMP_PRECISION,
            balancesBefore.poolTokens
        );
        uint256 expectedAmountOut = StableMath.computeOutGivenExactIn(
            DEFAULT_AMP_FACTOR * StableMath.AMP_PRECISION,
            balancesBefore.poolTokens,
            daiIdx,
            usdcIdx,
            daiExactAmountIn,
            poolInvariant
        );

        // Swap DAI for USDC, bringing pool nearer balance
        vm.prank(bob);
        router.swapSingleTokenExactIn(pool, dai, usdc, daiExactAmountIn, 0, MAX_UINT256, false, bytes(""));

        BaseVaultTest.Balances memory balancesAfter = getBalances(lp);

        // Measure actual amount out, which is expectedAmountOut - swapFeeAmount
        uint256 actualAmountOut = balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx];
        uint256 swapFeeAmount = expectedAmountOut - actualAmountOut;

        // Check if swap fee percentage applied is 10% (static fee percentage, since pool was taken nearer to
        // equilibrium)
        assertEq(swapFeeAmount, expectedAmountOut.mulUp(SWAP_FEE_PERCENTAGE), "Swap Fee Amount is wrong");

        // Bob balances (Bob deposited DAI to receive USDC)
        assertEq(
            balancesBefore.bobTokens[daiIdx] - balancesAfter.bobTokens[daiIdx],
            daiExactAmountIn,
            "Bob DAI balance is wrong"
        );
        assertEq(
            balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx],
            expectedAmountOut - swapFeeAmount,
            "Bob USDC balance is wrong"
        );

        // Pool balances (Pool received DAI and returned USDC)
        assertEq(
            balancesAfter.poolTokens[daiIdx] - balancesBefore.poolTokens[daiIdx],
            daiExactAmountIn,
            "Pool DAI balance is wrong"
        );
        // Since Protocol Swap Fee is 0 (was not set in this test) all swap fee amount returned to the pool
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            expectedAmountOut - swapFeeAmount,
            "Pool USDC balance is wrong"
        );

        // Vault Balances (Must reflect pool)
        assertEq(
            balancesAfter.vaultTokens[daiIdx] - balancesBefore.vaultTokens[daiIdx],
            daiExactAmountIn,
            "Vault DAI balance is wrong"
        );
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            expectedAmountOut - swapFeeAmount,
            "Vault USDC balance is wrong"
        );

        // Vault Reserves (Must reflect vault balances)
        assertEq(
            balancesAfter.vaultReserves[daiIdx] - balancesBefore.vaultReserves[daiIdx],
            daiExactAmountIn,
            "Vault DAI reserve is wrong"
        );
        assertEq(
            balancesBefore.vaultReserves[usdcIdx] - balancesAfter.vaultReserves[usdcIdx],
            expectedAmountOut - swapFeeAmount,
            "Vault USDC reserve is wrong"
        );
    }

    // Test fee when pool is getting unbalanced
    function testSwapUnbalancingPoolFee() public {
        // Swap to meaningfully take the pool out of equilibrium
        uint256 daiExactAmountIn = poolInitAmount / 2;

        BaseVaultTest.Balances memory balancesBefore = getBalances(lp);
        // Since there's no rate providers, and all tokens are 18 decimals, scaled18 and raw values are equal.
        uint256[] memory balancesScaled18 = balancesBefore.poolTokens;

        // Calculate the expected amount out (amount out without fees).
        uint256 poolInvariant = StableMath.computeInvariant(
            DEFAULT_AMP_FACTOR * StableMath.AMP_PRECISION,
            balancesScaled18
        );
        uint256 expectedAmountOut = StableMath.computeOutGivenExactIn(
            DEFAULT_AMP_FACTOR * StableMath.AMP_PRECISION,
            balancesScaled18,
            daiIdx,
            usdcIdx,
            daiExactAmountIn,
            poolInvariant
        );

        // Call dynamic fee hook to fetch the expected swap fee percentage
        vm.prank(address(vault));
        (, uint256 expectedSwapFeePercentage) = DirectionalFeeHookExample(poolHooksContract)
            .onComputeDynamicSwapFeePercentage(
                IBasePool.PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: daiExactAmountIn,
                    balancesScaled18: balancesScaled18,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(0), // The router is not used by the hook
                    userData: bytes("") // User data is not used by the hook
                }),
                pool,
                SWAP_FEE_PERCENTAGE
            );

        // Brings pool nearer equilibrium by swapping DAI for USDC
        vm.prank(bob);
        router.swapSingleTokenExactIn(pool, dai, usdc, daiExactAmountIn, 0, MAX_UINT256, false, bytes(""));

        BaseVaultTest.Balances memory balancesAfter = getBalances(lp);

        // Measure actual amount out, which is expectedAmountOut - swapFeeAmount
        uint256 actualAmountOut = balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx];
        uint256 actualSwapFeeAmount = expectedAmountOut - actualAmountOut;

        // Check if swap fee percentage applied is expected swap fee percentage (since pool was taken farther from
        // equilibrium)
        assertEq(actualSwapFeeAmount, expectedAmountOut.mulUp(expectedSwapFeePercentage), "Swap Fee Amount is wrong");
        assertGt(expectedSwapFeePercentage, SWAP_FEE_PERCENTAGE, "Expected Swap Fee Percentage not greater than 10%");

        // Bob balances (Bob deposited DAI to receive USDC)
        assertEq(
            balancesBefore.bobTokens[daiIdx] - balancesAfter.bobTokens[daiIdx],
            daiExactAmountIn,
            "Bob DAI balance is wrong"
        );
        assertEq(
            balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx],
            expectedAmountOut - actualSwapFeeAmount,
            "Bob USDC balance is wrong"
        );

        // Pool balances (Pool received DAI and returned USDC)
        assertEq(
            balancesAfter.poolTokens[daiIdx] - balancesBefore.poolTokens[daiIdx],
            daiExactAmountIn,
            "Pool DAI balance is wrong"
        );
        // Since Protocol Swap Fee is 0 (was not set in this test) all swap fee amount returned to the pool
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            expectedAmountOut - actualSwapFeeAmount,
            "Pool USDC balance is wrong"
        );

        // Vault Balances (Must reflect pool)
        assertEq(
            balancesAfter.vaultTokens[daiIdx] - balancesBefore.vaultTokens[daiIdx],
            daiExactAmountIn,
            "Vault DAI balance is wrong"
        );
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            expectedAmountOut - actualSwapFeeAmount,
            "Vault USDC balance is wrong"
        );

        // Vault Reserves (Must reflect vault balances)
        assertEq(
            balancesAfter.vaultReserves[daiIdx] - balancesBefore.vaultReserves[daiIdx],
            daiExactAmountIn,
            "Vault DAI reserve is wrong"
        );
        assertEq(
            balancesBefore.vaultReserves[usdcIdx] - balancesAfter.vaultReserves[usdcIdx],
            expectedAmountOut - actualSwapFeeAmount,
            "Vault USDC reserve is wrong"
        );
    }

    // Registry tests require a new pool, because an existent pool may be already registered
    function _createPoolToRegister() private returns (address newPool) {
        newPool = address(new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL"));
        vm.label(newPool, "Directional Fee Pool");
    }

    function _registerPoolWithHook(address directionalFeePool, TokenConfig[] memory tokenConfig) private {
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = lp;

        LiquidityManagement memory liquidityManagement;

        factoryMock.registerPool(directionalFeePool, tokenConfig, roleAccounts, poolHooksContract, liquidityManagement);
    }
}
