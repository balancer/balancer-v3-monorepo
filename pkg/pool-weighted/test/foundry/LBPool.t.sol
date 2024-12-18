// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    TokenConfig,
    PoolRoleAccounts,
    PoolSwapParams,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BasePoolTest } from "@balancer-labs/v3-vault/test/foundry/utils/BasePoolTest.sol";
import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { RouterMock } from "@balancer-labs/v3-vault/contracts/test/RouterMock.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { LBPoolFactory } from "../../contracts/lbp/LBPoolFactory.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";
import { LBPool } from "../../contracts/lbp/LBPool.sol";

contract LBPoolTest is BasePoolTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 constant DEFAULT_SWAP_FEE = 1e16; // 1%
    uint256 constant TOKEN_AMOUNT = 1e3 * 1e18;

    uint256[] internal weights;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        expectedAddLiquidityBptAmountOut = TOKEN_AMOUNT;
        tokenAmountIn = TOKEN_AMOUNT / 4;
        isTestSwapFeeEnabled = false;

        BasePoolTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        poolMinSwapFeePercentage = 0.001e16; // 0.001%
        poolMaxSwapFeePercentage = 10e16;
    }

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        IERC20[] memory sortedTokens = InputHelpers.sortTokens(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );
        for (uint256 i = 0; i < sortedTokens.length; i++) {
            poolTokens.push(sortedTokens[i]);
            tokenAmounts.push(TOKEN_AMOUNT);
        }

        string memory poolVersion = "Pool v1";

        factory = new LBPoolFactory(IVault(address(vault)), 365 days, "Factory v1", poolVersion, address(router));
        weights = [uint256(50e16), uint256(50e16)].toMemoryArray();

        // Allow pools created by `factory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        string memory name = "LB Pool";
        string memory symbol = "LB_POOL";

        poolArgs = abi.encode(
            WeightedPool.NewPoolParams({
                name: name,
                symbol: symbol,
                numTokens: sortedTokens.length,
                normalizedWeights: weights,
                version: poolVersion
            }),
            vault,
            bob,
            true,
            address(router)
        );

        newPool = LBPoolFactory(address(factory)).create(
            name,
            symbol,
            vault.buildTokenConfig(sortedTokens),
            weights,
            DEFAULT_SWAP_FEE,
            bob,
            true,
            ZERO_BYTES32
        );
    }

    function testInitialize() public view override {
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        for (uint256 i = 0; i < poolTokens.length; ++i) {
            // Tokens are transferred from bob (lp/owner)
            assertEq(
                defaultBalance - poolTokens[i].balanceOf(bob),
                tokenAmounts[i],
                string.concat("LP: Wrong balance for ", Strings.toString(i))
            );

            // Tokens are stored in the Vault
            assertEq(
                poolTokens[i].balanceOf(address(vault)),
                tokenAmounts[i],
                string.concat("LP: Vault balance for ", Strings.toString(i))
            );

            // Tokens are deposited to the pool
            assertEq(
                balances[i],
                tokenAmounts[i],
                string.concat("Pool: Wrong token balance for ", Strings.toString(i))
            );
        }

        // should mint correct amount of BPT poolTokens
        // Account for the precision loss
        assertApproxEqAbs(IERC20(pool).balanceOf(bob), bptAmountOut, DELTA, "LP: Wrong bptAmountOut");
        assertApproxEqAbs(bptAmountOut, expectedAddLiquidityBptAmountOut, DELTA, "Wrong bptAmountOut");
    }

    function initPool() internal override {
        vm.startPrank(bob);
        bptAmountOut = _initPool(
            pool,
            tokenAmounts,
            // Account for the precision loss
            expectedAddLiquidityBptAmountOut - DELTA
        );
        vm.stopPrank();
    }

    // overriding b/c bob needs to be the LP and has contributed double the "normal" amount of tokens
    function testAddLiquidity() public override {
        uint256 oldBptAmount = IERC20(pool).balanceOf(bob);
        vm.prank(bob);
        bptAmountOut = router.addLiquidityUnbalanced(pool, tokenAmounts, tokenAmountIn - DELTA, false, bytes(""));

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        for (uint256 i = 0; i < poolTokens.length; ++i) {
            // Tokens are transferred from Bob
            assertEq(
                defaultBalance - poolTokens[i].balanceOf(bob),
                tokenAmounts[i] * 2, // x2 because bob (as owner) did init join and subsequent join
                string.concat("LP: Wrong token balance for ", Strings.toString(i))
            );

            // Tokens are stored in the Vault
            assertEq(
                poolTokens[i].balanceOf(address(vault)),
                tokenAmounts[i] * 2,
                string.concat("Vault: Wrong token balance for ", Strings.toString(i))
            );

            assertEq(
                balances[i],
                tokenAmounts[i] * 2,
                string.concat("Pool: Wrong token balance for ", Strings.toString(i))
            );
        }

        uint256 newBptAmount = IERC20(pool).balanceOf(bob);

        // should mint correct amount of BPT poolTokens
        assertApproxEqAbs(newBptAmount - oldBptAmount, bptAmountOut, DELTA, "LP: Wrong bptAmountOut");
        assertApproxEqAbs(bptAmountOut, expectedAddLiquidityBptAmountOut, DELTA, "Wrong bptAmountOut");
    }

    // overriding b/c bob has swap fee authority, not governance
    // TODO: why does this test need to change swap fee anyway?
    function testAddLiquidityUnbalanced() public override {
        vm.prank(bob);
        vault.setStaticSwapFeePercentage(pool, 10e16);

        uint256[] memory amountsIn = tokenAmounts;
        amountsIn[0] = amountsIn[0].mulDown(IBasePool(pool).getMaximumInvariantRatio());
        vm.prank(bob);

        router.addLiquidityUnbalanced(pool, amountsIn, 0, false, bytes(""));
    }

    function testRemoveLiquidity() public override {
        vm.startPrank(bob);
        uint256 oldBptAmount = IERC20(pool).balanceOf(bob);
        router.addLiquidityUnbalanced(pool, tokenAmounts, tokenAmountIn - DELTA, false, bytes(""));
        uint256 newBptAmount = IERC20(pool).balanceOf(bob);

        IERC20(pool).approve(address(vault), MAX_UINT256);

        uint256 bptAmountIn = newBptAmount - oldBptAmount;

        uint256[] memory minAmountsOut = new uint256[](poolTokens.length);
        for (uint256 i = 0; i < poolTokens.length; ++i) {
            minAmountsOut[i] = less(tokenAmounts[i], 1e4);
        }

        // Prevent roundtrip fee
        vault.manualSetAddLiquidityCalledFlag(pool, false);

        uint256[] memory amountsOut = router.removeLiquidityProportional(
            pool,
            bptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );

        vm.stopPrank();

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        for (uint256 i = 0; i < poolTokens.length; ++i) {
            // Tokens are transferred to Bob
            assertApproxEqAbs(
                poolTokens[i].balanceOf(bob) + TOKEN_AMOUNT, //add TOKEN_AMOUNT to account for init join
                defaultBalance,
                DELTA,
                string.concat("LP: Wrong token balance for ", Strings.toString(i))
            );

            // Tokens are stored in the Vault
            assertApproxEqAbs(
                poolTokens[i].balanceOf(address(vault)),
                tokenAmounts[i],
                DELTA,
                string.concat("Vault: Wrong token balance for ", Strings.toString(i))
            );

            // Tokens are deposited to the pool
            assertApproxEqAbs(
                balances[i],
                tokenAmounts[i],
                DELTA,
                string.concat("Pool: Wrong token balance for ", Strings.toString(i))
            );

            // amountsOut are correct
            assertApproxEqAbs(
                amountsOut[i],
                tokenAmounts[i],
                DELTA,
                string.concat("Wrong token amountOut for ", Strings.toString(i))
            );
        }

        // should return to correct amount of BPT poolTokens
        assertEq(IERC20(pool).balanceOf(bob), oldBptAmount, "LP: Wrong BPT balance");
    }

    function testSwap() public override {
        if (!isTestSwapFeeEnabled) {
            vault.manuallySetSwapFee(pool, 0);
        }

        IERC20 tokenIn = poolTokens[tokenIndexIn];
        IERC20 tokenOut = poolTokens[tokenIndexOut];

        uint256 bobBeforeBalanceTokenOut = tokenOut.balanceOf(bob);
        uint256 bobBeforeBalanceTokenIn = tokenIn.balanceOf(bob);

        vm.prank(bob);
        uint256 amountCalculated = router.swapSingleTokenExactIn(
            pool,
            tokenIn,
            tokenOut,
            tokenAmountIn,
            less(tokenAmountOut, 1e3),
            MAX_UINT256,
            false,
            bytes("")
        );

        // Tokens are transferred from Bob
        assertEq(tokenOut.balanceOf(bob), bobBeforeBalanceTokenOut + amountCalculated, "LP: Wrong tokenOut balance");
        assertEq(tokenIn.balanceOf(bob), bobBeforeBalanceTokenIn - tokenAmountIn, "LP: Wrong tokenIn balance");

        // Tokens are stored in the Vault
        assertEq(
            tokenOut.balanceOf(address(vault)),
            tokenAmounts[tokenIndexOut] - amountCalculated,
            "Vault: Wrong tokenOut balance"
        );
        assertEq(
            tokenIn.balanceOf(address(vault)),
            tokenAmounts[tokenIndexIn] + tokenAmountIn,
            "Vault: Wrong tokenIn balance"
        );

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(pool);

        assertEq(balances[tokenIndexIn], tokenAmounts[tokenIndexIn] + tokenAmountIn, "Pool: Wrong tokenIn balance");
        assertEq(
            balances[tokenIndexOut],
            tokenAmounts[tokenIndexOut] - amountCalculated,
            "Pool: Wrong tokenOut balance"
        );
    }

    function testOnlyOwnerCanBeLP() public {
        uint256[] memory amounts = [TOKEN_AMOUNT, TOKEN_AMOUNT].toMemoryArray();

        vm.startPrank(bob);
        router.addLiquidityUnbalanced(address(pool), amounts, 0, false, "");
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BeforeAddLiquidityHookFailed.selector));
        router.addLiquidityUnbalanced(address(pool), amounts, 0, false, "");
        vm.stopPrank();
    }

    function testSwapRestrictions() public {
        // Ensure swaps are initially enabled
        assertTrue(LBPool(address(pool)).getSwapEnabled(), "Swaps should be enabled initially");

        // Test swap when enabled
        vm.prank(alice);
        router.swapSingleTokenExactIn(
            address(pool),
            IERC20(dai),
            IERC20(usdc),
            TOKEN_AMOUNT / 10,
            0,
            block.timestamp + 1 hours,
            false,
            ""
        );

        // Disable swaps
        vm.prank(bob);
        LBPool(address(pool)).setSwapEnabled(false);

        // Verify swaps are disabled
        assertFalse(LBPool(address(pool)).getSwapEnabled(), "Swaps should be disabled");

        // Test swap when disabled
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LBPool.SwapsDisabled.selector));
        router.swapSingleTokenExactIn(
            address(pool),
            IERC20(dai),
            IERC20(usdc),
            TOKEN_AMOUNT / 10,
            0,
            block.timestamp + 1 hours,
            false,
            ""
        );

        // Re-enable swaps
        vm.prank(bob);
        LBPool(address(pool)).setSwapEnabled(true);

        // Verify swaps are re-enabled
        assertTrue(LBPool(address(pool)).getSwapEnabled(), "Swaps should be re-enabled");

        // Test swap after re-enabling
        vm.prank(alice);
        router.swapSingleTokenExactIn(
            address(pool),
            IERC20(dai),
            IERC20(usdc),
            TOKEN_AMOUNT / 10,
            0,
            block.timestamp + 1 hours,
            false,
            ""
        );
    }

    function testEnsureNoTimeOverflow() public {
        uint256 blockDotTimestampTestStart = block.timestamp;
        uint256[] memory endWeights = new uint256[](2);
        endWeights[0] = 0.01e18; // 1%
        endWeights[1] = 0.99e18; // 99%

        vm.prank(bob);
        vm.expectRevert(stdError.arithmeticError);
        LBPool(address(pool)).updateWeightsGradually(blockDotTimestampTestStart, type(uint32).max + 1, endWeights);
    }

    function testQuerySwapDuringWeightUpdate() public {
        // Cache original time to avoid issues from `block.timestamp` during `vm.warp`
        uint256 blockDotTimestampTestStart = block.timestamp;

        uint256 testDuration = 1 days;
        uint256 weightUpdateStep = 1 hours;
        uint256 constantWeightDuration = 6 hours;
        uint256 startTime = blockDotTimestampTestStart + constantWeightDuration;

        uint256[] memory endWeights = new uint256[](2);
        endWeights[0] = 0.01e18; // 1%
        endWeights[1] = 0.99e18; // 99%

        uint256 amountIn = TOKEN_AMOUNT / 10;
        uint256 constantWeightSteps = constantWeightDuration / weightUpdateStep;
        uint256 weightUpdateSteps = testDuration / weightUpdateStep;

        // Start the gradual weight update
        vm.prank(bob);
        LBPool(address(pool)).updateWeightsGradually(startTime, startTime + testDuration, endWeights);

        uint256 prevAmountOut;
        uint256 amountOut;

        // Perform query swaps before the weight update starts
        vm.warp(blockDotTimestampTestStart);
        prevAmountOut = _executeAndUndoSwap(amountIn);
        for (uint256 i = 1; i < constantWeightSteps; i++) {
            uint256 currTime = blockDotTimestampTestStart + i * weightUpdateStep;
            vm.warp(currTime);
            amountOut = _executeAndUndoSwap(amountIn);
            assertEq(amountOut, prevAmountOut, "Amount out should remain constant before weight update");
            prevAmountOut = amountOut;
        }

        // Perform query swaps during the weight update
        vm.warp(startTime);
        prevAmountOut = _executeAndUndoSwap(amountIn);
        for (uint256 i = 1; i <= weightUpdateSteps; i++) {
            vm.warp(startTime + i * weightUpdateStep);
            amountOut = _executeAndUndoSwap(amountIn);
            assertTrue(amountOut > prevAmountOut, "Amount out should increase during weight update");
            prevAmountOut = amountOut;
        }

        // Perform query swaps after the weight update ends
        vm.warp(startTime + testDuration);
        prevAmountOut = _executeAndUndoSwap(amountIn);
        for (uint256 i = 1; i < constantWeightSteps; i++) {
            vm.warp(startTime + testDuration + i * weightUpdateStep);
            amountOut = _executeAndUndoSwap(amountIn);
            assertEq(amountOut, prevAmountOut, "Amount out should remain constant after weight update");
            prevAmountOut = amountOut;
        }
    }

    function testGetGradualWeightUpdateParams() public {
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + 7 days;
        uint256[] memory endWeights = new uint256[](2);
        endWeights[0] = 0.2e18; // 20%
        endWeights[1] = 0.8e18; // 80%

        vm.prank(bob);
        LBPool(address(pool)).updateWeightsGradually(startTime, endTime, endWeights);

        (uint256 returnedStartTime, uint256 returnedEndTime, uint256[] memory returnedEndWeights) = LBPool(
            address(pool)
        ).getGradualWeightUpdateParams();

        assertEq(returnedStartTime, startTime, "Start time should match");
        assertEq(returnedEndTime, endTime, "End time should match");
        assertEq(returnedEndWeights.length, endWeights.length, "End weights length should match");
        for (uint256 i = 0; i < endWeights.length; i++) {
            assertEq(returnedEndWeights[i], endWeights[i], "End weight should match");
        }
    }

    function testUpdateWeightsGraduallyMinWeightRevert() public {
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + 7 days;
        uint256[] memory endWeights = new uint256[](2);
        endWeights[0] = 0.0001e18; // 0.01%
        endWeights[1] = 0.9999e18; // 99.99%

        vm.prank(bob);
        vm.expectRevert(WeightedPool.MinWeight.selector);
        LBPool(address(pool)).updateWeightsGradually(startTime, endTime, endWeights);
    }

    function testUpdateWeightsGraduallyNormalizedWeightInvariantRevert() public {
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + 7 days;
        uint256[] memory endWeights = new uint256[](2);
        endWeights[0] = 0.6e18; // 60%
        endWeights[1] = 0.5e18; // 50%

        vm.prank(bob);
        vm.expectRevert(WeightedPool.NormalizedWeightInvariant.selector);
        LBPool(address(pool)).updateWeightsGradually(startTime, endTime, endWeights);
    }

    function testAddLiquidityRouterNotTrusted() public {
        RouterMock mockRouter = new RouterMock(IVault(address(vault)), weth, permit2);

        uint256[] memory amounts = [TOKEN_AMOUNT, TOKEN_AMOUNT].toMemoryArray();

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(LBPool.RouterNotTrusted.selector));
        mockRouter.addLiquidityUnbalanced(address(pool), amounts, 0, false, "");
        vm.stopPrank();
    }

    function testInvalidTokenCount() public {
        IERC20[] memory sortedTokens1 = InputHelpers.sortTokens([address(dai)].toMemoryArray().asIERC20());
        IERC20[] memory sortedTokens3 = InputHelpers.sortTokens(
            [address(dai), address(usdc), address(weth)].toMemoryArray().asIERC20()
        );

        TokenConfig[] memory tokenConfig1 = vault.buildTokenConfig(sortedTokens1);
        TokenConfig[] memory tokenConfig3 = vault.buildTokenConfig(sortedTokens3);

        // Attempt to create a pool with 1 token
        // Doesn't throw InputHelpers.InputLengthMismatch.selector b/c create3 intercepts error
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        LBPoolFactory(address(factory)).create(
            "Invalid Pool 1",
            "IP1",
            tokenConfig1,
            [uint256(1e18)].toMemoryArray(),
            DEFAULT_SWAP_FEE,
            bob,
            true,
            ZERO_BYTES32
        );

        // Attempt to create a pool with 3 tokens
        // Doesn't throw InputHelpers.InputLengthMismatch.selector b/c create3 intercepts error
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        LBPoolFactory(address(factory)).create(
            "Invalid Pool 3",
            "IP3",
            tokenConfig3,
            [uint256(0.3e18), uint256(0.3e18), uint256(0.4e18)].toMemoryArray(),
            DEFAULT_SWAP_FEE,
            bob,
            true,
            ZERO_BYTES32
        );
    }

    function testMismatchedWeightsAndTokens() public {
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(poolTokens);

        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        LBPoolFactory(address(factory)).create(
            "Mismatched Pool",
            "MP",
            tokenConfig,
            [uint256(1e18)].toMemoryArray(),
            DEFAULT_SWAP_FEE,
            bob,
            true,
            ZERO_BYTES32
        );
    }

    function testInitializedWithSwapsDisabled() public {
        LBPool swapsDisabledPool = LBPool(
            LBPoolFactory(address(factory)).create(
                "Swaps Disabled Pool",
                "SDP",
                vault.buildTokenConfig(poolTokens),
                weights,
                DEFAULT_SWAP_FEE,
                bob,
                false, // swapEnabledOnStart set to false
                keccak256(abi.encodePacked(block.timestamp)) // generate pseudorandom salt to avoid collision
            )
        );

        assertFalse(swapsDisabledPool.getSwapEnabled(), "Swaps should be disabled on initialization");

        // Initialize to make swapping (or at least trying) possible
        vm.startPrank(bob);
        bptAmountOut = _initPool(
            address(swapsDisabledPool),
            tokenAmounts,
            // Account for the precision loss
            expectedAddLiquidityBptAmountOut - DELTA
        );
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(LBPool.SwapsDisabled.selector));
        router.swapSingleTokenExactIn(
            address(swapsDisabledPool),
            IERC20(dai),
            IERC20(usdc),
            TOKEN_AMOUNT / 10,
            0,
            block.timestamp + 1 hours,
            false,
            ""
        );
        vm.stopPrank();
    }

    function testUpdateWeightsGraduallyMismatchedEndWeightsTooFew() public {
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + 7 days;
        uint256[] memory endWeights = new uint256[](1); // Too few end weights
        endWeights[0] = 1e18;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(InputHelpers.InputLengthMismatch.selector));
        LBPool(address(pool)).updateWeightsGradually(startTime, endTime, endWeights);
    }

    function testUpdateWeightsGraduallyMismatchedEndWeightsTooMany() public {
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + 7 days;
        uint256[] memory endWeights = new uint256[](3); // Too many end weights
        endWeights[0] = 0.3e18;
        endWeights[1] = 0.3e18;
        endWeights[2] = 0.4e18;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(InputHelpers.InputLengthMismatch.selector));
        LBPool(address(pool)).updateWeightsGradually(startTime, endTime, endWeights);
    }

    function testNonOwnerCannotUpdateWeights() public {
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + 7 days;
        uint256[] memory endWeights = new uint256[](2);
        endWeights[0] = 0.7e18;
        endWeights[1] = 0.3e18;

        vm.prank(alice); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(alice)));
        LBPool(address(pool)).updateWeightsGradually(startTime, endTime, endWeights);
    }

    function testOnSwapInvalidTokenIndex() public {
        vm.prank(address(vault));

        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 1e18,
            balancesScaled18: new uint256[](3), // add an extra (non-existent) value to give the bad index a balance
            indexIn: 2, // Invalid token index
            indexOut: 0,
            router: address(router),
            userData: ""
        });

        vm.expectRevert(IVaultErrors.InvalidToken.selector);
        LBPool(pool).onSwap(request);
    }

    function _executeAndUndoSwap(uint256 amountIn) internal returns (uint256) {
        // Create a storage checkpoint
        uint256 snapshot = vm.snapshot();

        try this.executeSwap(amountIn) returns (uint256 amountOut) {
            // Revert to the snapshot to undo the swap
            vm.revertTo(snapshot);
            return amountOut;
        } catch Error(string memory reason) {
            vm.revertTo(snapshot);
            revert(reason);
        } catch {
            vm.revertTo(snapshot);
            revert("Low level error during swap");
        }
    }

    function executeSwap(uint256 amountIn) external returns (uint256) {
        // Ensure this contract has enough tokens and allowance
        deal(address(dai), address(bob), amountIn);
        vm.prank(bob);
        IERC20(dai).approve(address(router), amountIn);

        // Perform the actual swap
        vm.prank(bob);
        return
            router.swapSingleTokenExactIn(
                address(pool),
                IERC20(dai),
                IERC20(usdc),
                amountIn,
                0, // minAmountOut: Set to 0 or a minimum amount if desired
                block.timestamp, // deadline = now to ensure it won't timeout
                false, // wethIsEth: Set to false assuming DAI and USDC are not ETH
                "" // userData: Empty bytes as no additional data is needed
            );
    }
}
