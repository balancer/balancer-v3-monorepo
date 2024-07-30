// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { ProtocolFeeControllerMock } from "@balancer-labs/v3-vault/contracts/test/ProtocolFeeControllerMock.sol";
import { E2eSwapTest } from "@balancer-labs/v3-vault/test/foundry/E2eSwap.t.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { WeightedPoolFactory } from "../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";
import { WeightedPoolMock } from "../../contracts/test/WeightedPoolMock.sol";

contract E2eSwapWeightedTest is E2eSwapTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 internal constant DEFAULT_SWAP_FEE = 1e16; // 1%

    uint256 internal poolCreationNonce;

    WeightedPoolMock internal poolWithChangeableWeights;

    function setUp() public override {
        E2eSwapTest.setUp();
        poolWithChangeableWeights = WeightedPoolMock(_createAndInitPoolWithChangeableWeights());
    }

    function _setUpVariables() internal override {
        sender = lp;
        poolCreator = lp;

        // If there are swap fees, the amountCalculated may be lower than MIN_TRADE_AMOUNT. So, multiplying
        // MIN_TRADE_AMOUNT by 1e4 creates a margin (especially for operations in the edge of the price curve).
        minSwapAmountDai = 1e4 * MIN_TRADE_AMOUNT;
        minSwapAmountUsdc = 1e4 * MIN_TRADE_AMOUNT;

        // Divide init amount by 10 to make sure weighted math ratios are respected (Cannot trade more than 30% of pool
        // balance).
        maxSwapAmountDai = poolInitAmount / 10;
        maxSwapAmountUsdc = poolInitAmount / 10;

        // 0.0001% max swap fee.
        minPoolSwapFeePercentage = 1e12;
        // 10% max swap fee.
        maxPoolSwapFeePercentage = 1e17;
    }

    function testDoExactInUndoExactInDifferentWeights(uint256 weightDai) public {
        // Change between 1% and 99%.
        weightDai = bound(weightDai, 1e16, 99e16);
        uint256[2] memory newWeights;
        newWeights[daiIdx] = weightDai;
        newWeights[usdcIdx] = FixedPoint.ONE - weightDai;

        poolWithChangeableWeights.setNormalizedWeights(newWeights);

        uint256[] memory newPoolBalances = new uint256[](2);
        // This operation will change the invariant of the pool, but what matters is the proportion of each token.
        newPoolBalances[daiIdx] = (poolInitAmount).mulDown(newWeights[daiIdx]);
        newPoolBalances[usdcIdx] = (poolInitAmount).mulDown(newWeights[usdcIdx]);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(poolWithChangeableWeights));
        // liveBalances = rawBalances because rate is 1 and both tokens are 18 decimals.
        vault.manualSetPoolTokensAndBalances(
            address(poolWithChangeableWeights),
            tokens,
            newPoolBalances,
            newPoolBalances
        );

        // 25% of dai or usdc liquidity, the lowest value, to make sure the swap is executed.
        uint256 exactAmountIn = (
            newPoolBalances[daiIdx] > newPoolBalances[usdcIdx] ? newPoolBalances[usdcIdx] : newPoolBalances[daiIdx]
        ) / 4;

        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
        vault.manualUnsafeSetStaticSwapFeePercentage(address(poolWithChangeableWeights), 0);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountOutDo = router.swapSingleTokenExactIn(
            pool,
            dai,
            usdc,
            exactAmountIn,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 exactAmountOutUndo = router.swapSingleTokenExactIn(
            pool,
            usdc,
            dai,
            exactAmountOutDo,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);

        assertLe(exactAmountOutUndo, exactAmountIn, "Amount out undo should be <= exactAmountIn");
        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(balancesAfter.userTokens[daiIdx], balancesBefore.userTokens[daiIdx], "Wrong sender dai balance");
        assertLe(balancesAfter.userTokens[usdcIdx], balancesBefore.userTokens[usdcIdx], "Wrong sender usdc balance");
    }

    function testDoExactOutUndoExactOutDifferentWeights(uint256 weightDai) public {
        // Change between 1% and 99%.
        weightDai = bound(weightDai, 1e16, 99e16);
        uint256[2] memory newWeights;
        newWeights[daiIdx] = weightDai;
        newWeights[usdcIdx] = FixedPoint.ONE - weightDai;

        poolWithChangeableWeights.setNormalizedWeights(newWeights);

        uint256[] memory newPoolBalances = new uint256[](2);
        // This operation will change the invariant of the pool, but what matters is the proportion of each token.
        newPoolBalances[daiIdx] = (poolInitAmount).mulDown(newWeights[daiIdx]);
        newPoolBalances[usdcIdx] = (poolInitAmount).mulDown(newWeights[usdcIdx]);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(poolWithChangeableWeights));
        // liveBalances = rawBalances because rate is 1 and both tokens are 18 decimals.
        vault.manualSetPoolTokensAndBalances(
            address(poolWithChangeableWeights),
            tokens,
            newPoolBalances,
            newPoolBalances
        );

        // 25% of dai or usdc liquidity, the lowest value, to make sure the swap is executed.
        uint256 exactAmountOut = (
            newPoolBalances[daiIdx] > newPoolBalances[usdcIdx] ? newPoolBalances[usdcIdx] : newPoolBalances[daiIdx]
        ) / 4;

        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
        vault.manualUnsafeSetStaticSwapFeePercentage(address(poolWithChangeableWeights), 0);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountInDo = router.swapSingleTokenExactOut(
            pool,
            dai,
            usdc,
            exactAmountOut,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
            pool,
            usdc,
            dai,
            exactAmountInDo,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);

        assertGe(exactAmountInUndo, exactAmountOut, "Amount in undo should be >= exactAmountOut");
        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(balancesAfter.userTokens[daiIdx], balancesBefore.userTokens[daiIdx], "Wrong sender dai balance");
        assertLe(balancesAfter.userTokens[usdcIdx], balancesBefore.userTokens[usdcIdx], "Wrong sender usdc balance");
    }

    /// @notice Overrides BaseVaultTest _createPool(). This pool is used by E2eSwapTest tests.
    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        WeightedPoolFactory factory = new WeightedPoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            "Pool v1"
        );
        PoolRoleAccounts memory roleAccounts;

        // Allow pools created by `factory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        WeightedPool newPool = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                vault.buildTokenConfig(tokens.asIERC20()),
                [uint256(50e16), uint256(50e16)].toMemoryArray(),
                roleAccounts,
                DEFAULT_SWAP_FEE, // 1% swap fee, but test will override it.
                poolHooksContract,
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                // NOTE: sends a unique salt
                bytes32(poolCreationNonce++)
            )
        );
        vm.label(address(newPool), label);

        // Cannot set pool creator directly with stable pool factory.
        vault.manualSetPoolCreator(address(newPool), lp);

        ProtocolFeeControllerMock feeController = ProtocolFeeControllerMock(address(vault.getProtocolFeeController()));
        feeController.manualSetPoolCreator(address(newPool), lp);

        return address(newPool);
    }

    /**
     * @notice Creates and initializes a weighted pool with a setter for weights, so weights can be changed without
     * initializing the pool again. This pool is used by fuzz tests that require changing the weight.
     */
    function _createAndInitPoolWithChangeableWeights() internal returns (address) {
        address[] memory tokens = [address(dai), address(usdc)].toMemoryArray();
        string memory label = "ChangeableWeightPool";

        LiquidityManagement memory liquidityManagement;
        PoolRoleAccounts memory roleAccounts;

        WeightedPoolMock weightedPool = new WeightedPoolMock(
            WeightedPool.NewPoolParams({
                name: label,
                symbol: "WEIGHTY",
                numTokens: 2,
                normalizedWeights: [uint256(50e16), uint256(50e16)].toMemoryArray(),
                version: "Version 1"
            }),
            vault
        );
        vm.label(address(weightedPool), label);

        vault.registerPool(
            address(weightedPool),
            vault.buildTokenConfig(tokens.asIERC20()),
            DEFAULT_SWAP_FEE,
            0,
            false,
            roleAccounts,
            address(0),
            liquidityManagement
        );

        uint256[] memory amountsIn = [poolInitAmount, poolInitAmount].toMemoryArray();

        vm.prank(lp);
        router.initialize(address(weightedPool), tokens.asIERC20(), amountsIn, 0, false, "");

        return address(weightedPool);
    }
}
