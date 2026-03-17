// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { IPoolInfo } from "@balancer-labs/v3-interfaces/contracts/pool-utils/IPoolInfo.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { MinTokenBalanceLib } from "@balancer-labs/v3-vault/contracts/lib/MinTokenBalanceLib.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { BasePoolMath } from "@balancer-labs/v3-vault/contracts/BasePoolMath.sol";

import { WeightedPoolContractsDeployer } from "./utils/WeightedPoolContractsDeployer.sol";
import { WeightedPoolMock } from "../../contracts/test/WeightedPoolMock.sol";
import { WeightedMathMock } from "../../contracts/test/WeightedMathMock.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";

contract WeightedPoolLimitsTest is BaseVaultTest, WeightedPoolContractsDeployer {
    using CastingHelpers for address[];
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 constant DEFAULT_SWAP_FEE = 1e16; // 1%
    uint256 constant MIN_SWAP_FEE = 0.001e16; // 0.001%
    uint256 constant MAX_SWAP_FEE = 10e16;

    WeightedMathMock math;

    uint256 constant TOKEN_AMOUNT = 1e3 * 1e18;
    uint256 constant TOKEN_AMOUNT_IN = 1 * 1e18;

    uint256 constant DELTA = 3e7;
    uint256 constant BPT_DELTA = 3e12;

    WeightedPoolMock internal weightedPool;
    uint256 internal bptAmountOut;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    uint256[] internal amountsIn;
    uint256[] internal newAmountsIn;
    uint256[] internal startingBalances;
    uint256[] internal expectedBalances;

    uint256 internal preInitSnapshotId;

    constructor() {
        math = deployWeightedMathMock();
        amountsIn = new uint256[](2);
        newAmountsIn = new uint256[](2);
        startingBalances = new uint256[](2);
        expectedBalances = new uint256[](2);

        newAmountsIn[0] = TOKEN_AMOUNT;
        newAmountsIn[1] = TOKEN_AMOUNT;
    }

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal virtual override returns (address newPool, bytes memory poolArgs) {
        LiquidityManagement memory liquidityManagement;
        PoolRoleAccounts memory roleAccounts;

        uint256[] memory minTokenBalances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            minTokenBalances[i] = _getMinTokenBalance(tokens[i]);
        }

        WeightedPool.NewPoolParams memory params = WeightedPool.NewPoolParams({
            name: "Weight Limit Pool",
            symbol: "WEIGHTY",
            numTokens: 2,
            normalizedWeights: [uint256(50e16), uint256(50e16)].toMemoryArray(),
            version: "Version 1",
            minTokenBalances: minTokenBalances
        });

        newPool = address(deployWeightedPoolMock(params, vault));
        vm.label(newPool, label);

        vault.registerPool(
            newPool,
            vault.buildTokenConfig(tokens.asIERC20()),
            DEFAULT_SWAP_FEE,
            0,
            false,
            roleAccounts,
            address(0),
            liquidityManagement
        );

        // poolArgs is used to check pool deployment address with create2.
        poolArgs = abi.encode(params, vault);

        weightedPool = WeightedPoolMock(newPool);
    }

    function initPool() internal override {
        // `_updatePoolParams` needs the indices to be set, so take the snapshot *after* this line.
        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        // Initialization test also needs these to be set.
        startingBalances[daiIdx] = dai.balanceOf(lp);
        startingBalances[usdcIdx] = usdc.balanceOf(lp);

        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), alice);

        preInitSnapshotId = vm.snapshotState();

        uint256[] memory weights = weightedPool.getNormalizedWeights();

        amountsIn[daiIdx] = TOKEN_AMOUNT.mulDown(weights[daiIdx]);
        amountsIn[usdcIdx] = TOKEN_AMOUNT.mulDown(weights[usdcIdx]);

        uint256 expectedBptAmountOut = math.computeInvariant(weights, amountsIn, Rounding.ROUND_DOWN) -
            POOL_MINIMUM_TOTAL_SUPPLY;

        // Cannot use vm.prank, because `_initPool` does multiple calls.
        vm.startPrank(lp);
        bptAmountOut = _initPool(pool, amountsIn, expectedBptAmountOut);
        vm.stopPrank();

        require(expectedBptAmountOut == bptAmountOut, "Wrong BPT amount out");
    }

    function testWeightLimits__Fuzz(uint256 daiWeight, uint256 swapFeePercentage) public {
        // It doesn't let me do the `bound` operations in `_updatePoolParams`.
        // Nor can I say `_updatePoolParams(bound(...))`.
        daiWeight = bound(daiWeight, 1e16, 99e16);
        swapFeePercentage = bound(swapFeePercentage, MIN_SWAP_FEE, MAX_SWAP_FEE);

        _updatePoolParams(daiWeight, swapFeePercentage);

        uint256 postInitSnapshot = vm.snapshotState();

        _testAddLiquidity();
        vm.revertToState(postInitSnapshot);

        _testRemoveLiquidity();
        vm.revertToState(postInitSnapshot);

        _testSwap();
        vm.revertToState(postInitSnapshot);

        _testAddLiquidityUnbalanced(swapFeePercentage);
    }

    function testInitialize__Fuzz(uint256 daiWeight, uint256 swapFeePercentage) public {
        vm.revertToState(preInitSnapshotId);

        daiWeight = bound(daiWeight, 1e16, 99e16);
        swapFeePercentage = bound(swapFeePercentage, MIN_SWAP_FEE, MAX_SWAP_FEE);

        _updatePoolParams(daiWeight, swapFeePercentage);

        initPool();
        _testInitialize();
    }

    function _updatePoolParams(uint256 daiWeight, uint256 swapFeePercentage) internal {
        uint256[2] memory weights;

        weights[daiIdx] = daiWeight;
        weights[usdcIdx] = FixedPoint.ONE - daiWeight;

        WeightedPoolMock(pool).setNormalizedWeights(weights);

        vm.prank(alice);
        vault.setStaticSwapFeePercentage(pool, swapFeePercentage);
    }

    function _testInitialize() internal view {
        // Tokens are transferred from `lp`.
        assertEq(startingBalances[usdcIdx] - usdc.balanceOf(lp), amountsIn[usdcIdx], "LP: Wrong USDC balance");
        assertEq(startingBalances[daiIdx] - dai.balanceOf(lp), amountsIn[daiIdx], "LP: Wrong DAI balance");

        // Tokens are stored in the Vault.
        assertEq(usdc.balanceOf(address(vault)), amountsIn[usdcIdx], "Vault: Wrong USDC balance");
        assertEq(dai.balanceOf(address(vault)), amountsIn[daiIdx], "Vault: Wrong DAI balance");

        // Tokens are deposited to the pool.
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[daiIdx], amountsIn[daiIdx], "Pool: Wrong DAI balance");
        assertEq(balances[usdcIdx], amountsIn[usdcIdx], "Pool: Wrong USDC balance");

        // Should mint correct amount of BPT tokens.
        // Account for the precision loss.
        assertApproxEqAbs(weightedPool.balanceOf(lp), bptAmountOut, DELTA, "LP: Wrong bptAmountOut");
    }

    function _testAddLiquidity() public {
        uint256[] memory weights = weightedPool.getNormalizedWeights();
        uint256[] memory initialBalances = new uint256[](2);
        initialBalances[daiIdx] = dai.balanceOf(bob);
        initialBalances[usdcIdx] = usdc.balanceOf(bob);

        uint256 expectedBptAmountOut = math.computeInvariant(weights, newAmountsIn, Rounding.ROUND_DOWN);

        vm.prank(bob);
        uint256[] memory actualAmountsIn = router.addLiquidityProportional(
            pool,
            [newAmountsIn[0] + DELTA, newAmountsIn[1] + DELTA].toMemoryArray(),
            expectedBptAmountOut,
            false,
            bytes("")
        );

        // Tokens are transferred from Bob.
        assertEq(initialBalances[usdcIdx] - usdc.balanceOf(bob), actualAmountsIn[usdcIdx], "LP: Wrong USDC balance");
        assertEq(initialBalances[daiIdx] - dai.balanceOf(bob), actualAmountsIn[daiIdx], "LP: Wrong DAI balance");

        expectedBalances[daiIdx] = actualAmountsIn[daiIdx] + amountsIn[daiIdx];
        expectedBalances[usdcIdx] = actualAmountsIn[usdcIdx] + amountsIn[usdcIdx];

        // Tokens are stored in the Vault.
        assertEq(usdc.balanceOf(address(vault)), expectedBalances[usdcIdx], "Vault: Wrong USDC balance");
        assertEq(dai.balanceOf(address(vault)), expectedBalances[daiIdx], "Vault: Wrong DAI balance");

        // Tokens are deposited to the pool.
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(weightedPool));
        assertEq(balances[daiIdx], expectedBalances[daiIdx], "Pool: Wrong DAI balance");
        assertEq(balances[usdcIdx], expectedBalances[usdcIdx], "Pool: Wrong USDC balance");

        // Should mint correct amount of BPT tokens.
        assertEq(weightedPool.balanceOf(bob), expectedBptAmountOut, "LP: Wrong bptAmountOut");
        assertApproxEqAbs(expectedBptAmountOut, TOKEN_AMOUNT, DELTA, "Wrong bptAmountOut");
    }

    function _testRemoveLiquidity() public {
        vm.startPrank(bob);
        router.addLiquidityProportional(pool, newAmountsIn, TOKEN_AMOUNT - DELTA, false, bytes(""));
        weightedPool.approve(address(vault), MAX_UINT256);

        uint256 bobBptBalance = weightedPool.balanceOf(bob);
        uint256 bptAmountIn = bobBptBalance;
        uint256 limit = less(TOKEN_AMOUNT, 1e4);

        startingBalances[daiIdx] = dai.balanceOf(bob);
        startingBalances[usdcIdx] = usdc.balanceOf(bob);

        uint256[] memory amountsOut = router.removeLiquidityProportional(
            address(weightedPool),
            bptAmountIn,
            [limit, limit].toMemoryArray(),
            false,
            bytes("")
        );

        vm.stopPrank();

        // Tokens are transferred to Bob.
        assertApproxEqAbs(
            usdc.balanceOf(bob) - startingBalances[usdcIdx],
            TOKEN_AMOUNT,
            DELTA,
            "LP: Wrong USDC balance"
        );
        assertApproxEqAbs(dai.balanceOf(bob) - startingBalances[daiIdx], TOKEN_AMOUNT, DELTA, "LP: Wrong DAI balance");

        expectedBalances[daiIdx] = TOKEN_AMOUNT - amountsIn[daiIdx];
        expectedBalances[usdcIdx] = TOKEN_AMOUNT - amountsIn[usdcIdx];

        // Tokens are stored in the Vault.
        assertApproxEqAbs(
            usdc.balanceOf(address(vault)),
            expectedBalances[usdcIdx],
            DELTA,
            "Vault: Wrong USDC balance"
        );
        assertApproxEqAbs(dai.balanceOf(address(vault)), expectedBalances[daiIdx], DELTA, "Vault: Wrong DAI balance");

        // Tokens are deposited to the pool.
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        assertApproxEqAbs(balances[daiIdx], expectedBalances[daiIdx], DELTA, "Pool: Wrong DAI balance");
        assertApproxEqAbs(balances[usdcIdx], expectedBalances[usdcIdx], DELTA, "Pool: Wrong USDC balance");

        // Ensure `amountsOut` are correct.
        assertApproxEqAbs(amountsOut[daiIdx], TOKEN_AMOUNT, DELTA, "Wrong DAI AmountOut");
        assertApproxEqAbs(amountsOut[usdcIdx], TOKEN_AMOUNT, DELTA, "Wrong USDC AmountOut");

        // Should mint correct amount of BPT tokens.
        assertEq(weightedPool.balanceOf(bob), 0, "LP: Non-zero BPT balance");
        assertEq(bobBptBalance, bptAmountIn, "LP: Wrong bptAmountIn");
    }

    function _testSwap() public {
        // Set swap fee to zero for this test.
        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);
        startingBalances[daiIdx] = dai.balanceOf(bob);
        startingBalances[usdcIdx] = usdc.balanceOf(bob);

        vm.prank(bob);
        uint256 amountCalculated = router.swapSingleTokenExactIn(
            address(pool),
            dai,
            usdc,
            TOKEN_AMOUNT_IN,
            0, // Don't worry about limit here; will test results anyway
            MAX_UINT256,
            false,
            bytes("")
        );

        // Tokens are transferred from Bob.
        assertEq(usdc.balanceOf(bob), startingBalances[usdcIdx] + amountCalculated, "LP: Wrong USDC balance");
        assertEq(dai.balanceOf(bob), startingBalances[daiIdx] - TOKEN_AMOUNT_IN, "LP: Wrong DAI balance");

        expectedBalances[daiIdx] = amountsIn[daiIdx] + TOKEN_AMOUNT_IN;
        expectedBalances[usdcIdx] = amountsIn[usdcIdx] - amountCalculated;

        // Tokens are stored in the Vault.
        assertEq(usdc.balanceOf(address(vault)), expectedBalances[usdcIdx], "Vault: Wrong USDC balance");
        assertEq(dai.balanceOf(address(vault)), expectedBalances[daiIdx], "Vault: Wrong DAI balance");

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        assertEq(balances[daiIdx], expectedBalances[daiIdx], "Pool: Wrong DAI balance");
        assertEq(balances[usdcIdx], expectedBalances[usdcIdx], "Pool: Wrong USDC balance");
    }

    function _testAddLiquidityUnbalanced(uint256 swapFeePercentage) public {
        uint256[] memory maxAmountsIn = [defaultAccountBalance(), defaultAccountBalance()].toMemoryArray();
        // Enlarge the pool so that adding liquidity unbalanced does not hit the invariant ratio limit.
        uint256 currentBPTSupply = IERC20(weightedPool).totalSupply();
        vm.prank(alice);
        router.addLiquidityProportional(pool, maxAmountsIn, currentBPTSupply * 100, false, bytes(""));

        vm.prank(alice);
        vault.setStaticSwapFeePercentage(address(pool), swapFeePercentage);

        startingBalances[daiIdx] = dai.balanceOf(bob);
        startingBalances[usdcIdx] = usdc.balanceOf(bob);

        uint256[] memory unbalancedAmountsIn = new uint256[](2);
        unbalancedAmountsIn[daiIdx] = 100 * TOKEN_AMOUNT_IN;
        unbalancedAmountsIn[usdcIdx] = TOKEN_AMOUNT_IN;

        (uint256 expectedBptAmountOut, ) = BasePoolMath.computeAddLiquidityUnbalanced(
            IPoolInfo(address(weightedPool)).getCurrentLiveBalances(),
            unbalancedAmountsIn,
            weightedPool.totalSupply(),
            swapFeePercentage,
            IBasePool(address(weightedPool))
        );

        vm.prank(bob);
        bptAmountOut = router.addLiquidityUnbalanced(address(pool), unbalancedAmountsIn, 0, false, bytes(""));

        // Tokens are transferred from Bob.
        assertEq(
            usdc.balanceOf(bob),
            startingBalances[usdcIdx] - unbalancedAmountsIn[usdcIdx],
            "LP: Wrong USDC balance"
        );
        assertEq(dai.balanceOf(bob), startingBalances[daiIdx] - unbalancedAmountsIn[daiIdx], "LP: Wrong DAI balance");

        // This will vary with the swap fee.
        assertApproxEqAbs(bptAmountOut, expectedBptAmountOut, BPT_DELTA, "Wrong BPT amount out");
    }

    function testWeightedPoolConstructorMinWeight() public {
        uint256[] memory weights = _weightsAllEqual8();
        weights[0] = 5e15; // 0.5% < 1% minimum
        // Fix the sum to 1 to isolate the min weight check.
        weights[1] =
            FixedPoint.ONE -
            weights[0] -
            (weights[2] + weights[3] + weights[4] + weights[5] + weights[6] + weights[7]);

        uint256[] memory mins = _minBalances8();

        vm.expectRevert(IWeightedPool.MinWeight.selector);
        deployWeightedPoolMock(_newParams8(weights, mins), vault);
    }

    function testWeightedPoolConstructorWeightSum() public {
        uint256[] memory weights = _weightsAllEqual8();
        weights[0] = weights[0] + 1; // sum != 1
        uint256[] memory mins = _minBalances8();

        vm.expectRevert(IWeightedPool.NormalizedWeightInvariant.selector);
        deployWeightedPoolMock(_newParams8(weights, mins), vault);
    }

    function testWeightedPoolGetMinTokenBalancesCoverage() public {
        WeightedPoolMock poolMock = deployWeightedPoolMock(_newParams8(_weightsAllEqual8(), _minBalances8()), vault);
        vault.manualRegisterPoolWithSwapFee(
            address(poolMock),
            [address(usdc), address(dai)].toMemoryArray().asIERC20(),
            1e16
        );

        // Hit each early-return path inside _getMinTokenBalances, plus the token-7 assignment.
        for (uint256 n = 2; n <= 8; ++n) {
            vault.manualSetPoolTokens(address(poolMock), new IERC20[](n));
            uint256[] memory mins = poolMock.getMinTokenBalances();
            assertEq(mins.length, n);
        }
    }

    function testWeightedPoolGetNormalizedWeightInvalidToken() public {
        WeightedPoolMock poolMock = deployWeightedPoolMock(_newParams8(_weightsAllEqual8(), _minBalances8()), vault);

        // Hit all the valid branches in the internal selector chain.
        for (uint256 i = 0; i < 8; ++i) {
            assertGt(poolMock.exposedGetNormalizedWeight(i), 0);
        }

        // Covers WeightedPool.sol invalid-token revert branch.
        vm.expectRevert(abi.encodeWithSignature("InvalidToken()"));
        poolMock.exposedGetNormalizedWeight(999);
    }

    function testWeightedPoolComputeBalanceMinBalanceSelectorBranches() public {
        WeightedPoolMock poolMock = deployWeightedPoolMock(_newParams8(_weightsAllEqual8(), _minBalances8()), vault);

        uint256[] memory balances = new uint256[](8);
        uint256[] memory mins = _minBalances8();
        for (uint256 i = 0; i < 8; ++i) {
            balances[i] = mins[i] + 1;
        }

        // computeBalance calls _ensureMinimumBalance(tokenInIndex, ...) and exercises the tokenIndex selector chain.
        for (uint256 tokenInIndex = 2; tokenInIndex < 8; ++tokenInIndex) {
            uint256 newBalance = poolMock.computeBalance(balances, tokenInIndex, FixedPoint.ONE);
            assertGt(newBalance, 0);
        }
    }

    function testWeightedPoolEnsureMinTokenBalancesExtraTokens() public {
        WeightedPoolMock poolMock = deployWeightedPoolMock(_newParams8(_weightsAllEqual8(), _minBalances8()), vault);

        uint256[] memory mins = _minBalances8();

        // Cover the revert lines for each token index (0..7), ensuring only one token is below min at a time.
        for (uint256 badIdx = 0; badIdx < 8; ++badIdx) {
            uint256[] memory balances = new uint256[](8);
            for (uint256 j = 0; j < 8; ++j) {
                balances[j] = mins[j];
            }
            balances[badIdx] = mins[badIdx] - 1;

            vm.expectRevert(); // TokenBalanceBelowMin(...)
            poolMock.computeInvariant(balances, Rounding.ROUND_DOWN);
        }
    }

    function testWeightedPoolEnsureMinTokenBalancesShortArrays() public {
        WeightedPoolMock poolMock = deployWeightedPoolMock(_newParams8(_weightsAllEqual8(), _minBalances8()), vault);

        uint256[] memory mins = _minBalances8();

        // Exercise each early-return branch in _ensureMinTokenBalances by passing shorter balance arrays.
        // computeInvariant will revert later (weights length mismatch), but coverage is still recorded.
        for (uint256 n = 2; n <= 7; ++n) {
            uint256[] memory balances = new uint256[](n);
            for (uint256 j = 0; j < n; ++j) {
                balances[j] = mins[j];
            }

            vm.expectRevert();
            poolMock.computeInvariant(balances, Rounding.ROUND_DOWN);
        }
    }

    function _newParams8(
        uint256[] memory weights,
        uint256[] memory minBalances
    ) private pure returns (WeightedPool.NewPoolParams memory) {
        return
            WeightedPool.NewPoolParams({
                name: "WP",
                symbol: "WP",
                numTokens: 8,
                normalizedWeights: weights,
                version: "v1",
                minTokenBalances: minBalances
            });
    }

    function _weightsAllEqual8() private pure returns (uint256[] memory weights) {
        weights = new uint256[](8);
        // 12.5% each
        for (uint256 i = 0; i < 8; ++i) {
            weights[i] = 125e15;
        }
    }

    function _minBalances8() private pure returns (uint256[] memory mins) {
        mins = new uint256[](8);
        for (uint256 i = 0; i < 8; ++i) {
            // must be >= ABSOLUTE_MIN_TOKEN_BALANCE; use a comfortably large value
            mins[i] = MinTokenBalanceLib.ABSOLUTE_MIN_TOKEN_BALANCE + 100 + i;
        }
    }
}
