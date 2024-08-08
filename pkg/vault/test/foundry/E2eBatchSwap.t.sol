// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract E2eBatchSwapTest is BaseVaultTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];

    address internal poolA;
    address internal poolB;
    address internal poolC;

    ERC20TestToken internal tokenA;
    ERC20TestToken internal tokenB;
    ERC20TestToken internal tokenC;
    ERC20TestToken internal tokenD;

    IERC20[] internal tokensToTrack;

    uint256 internal tokenAIdx;
    uint256 internal tokenBIdx;
    uint256 internal tokenCIdx;
    uint256 internal tokenDIdx;

    address internal sender;
    address internal poolCreator;

    uint256 internal minSwapAmountTokenA;
    uint256 internal maxSwapAmountTokenA;

    uint256 internal minSwapAmountTokenD;
    uint256 internal maxSwapAmountTokenD;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        IProtocolFeeController feeController = vault.getProtocolFeeController();
        IAuthentication feeControllerAuth = IAuthentication(address(feeController));

        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );

        _setUpVariables();

        // Set protocol and creator fees to 50%, so we can measure the charged fees.
        vm.prank(admin);
        feeController.setGlobalProtocolSwapFeePercentage(FIFTY_PERCENT);

        // Initialize pools that will be used by batch router.
        // Create poolA
        vm.startPrank(lp);
        poolA = _createPool([address(tokenA), address(tokenB)].toMemoryArray(), "poolA");
        _initPool(poolA, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        // Create poolB
        poolB = _createPool([address(tokenB), address(tokenC)].toMemoryArray(), "poolB");
        _initPool(poolB, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        // Create poolC
        poolC = _createPool([address(tokenC), address(tokenD)].toMemoryArray(), "PoolC");
        _initPool(poolC, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();

        vm.startPrank(poolCreator);
        // Set pool creator fee to 100%, so protocol + creator fees equals the total charged fees.
        feeController.setPoolCreatorSwapFeePercentage(poolA, FixedPoint.ONE);
        feeController.setPoolCreatorSwapFeePercentage(poolB, FixedPoint.ONE);
        feeController.setPoolCreatorSwapFeePercentage(poolC, FixedPoint.ONE);
        vm.stopPrank();

        tokensToTrack = [address(tokenA), address(tokenB), address(tokenC), address(tokenD)].toMemoryArray().asIERC20();

        // Idx of the token in relation to `tokensToTrack`.
        tokenAIdx = 0;
        tokenBIdx = 1;
        tokenCIdx = 2;
        tokenDIdx = 3;
    }

    /**
     * @notice Set up test variables (tokens, pool swap fee, swap sizes).
     * @dev When extending the test, override this function and set the same variables.
     */
    function _setUpVariables() internal virtual {
        tokenA = dai;
        tokenB = usdc;
        tokenC = ERC20TestToken(address(weth));
        tokenD = wsteth;

        sender = lp;
        poolCreator = lp;

        // If there are swap fees, the amountCalculated may be lower than MIN_TRADE_AMOUNT. So, multiplying
        // MIN_TRADE_AMOUNT by 10 creates a margin.
        minSwapAmountTokenA = 10 * MIN_TRADE_AMOUNT;
        maxSwapAmountTokenA = poolInitAmount / 2;

        minSwapAmountTokenD = 10 * MIN_TRADE_AMOUNT;
        maxSwapAmountTokenD = poolInitAmount / 2;
    }

    function testDoUndoExactIn__Fuzz(
        uint256 exactAmountIn,
        uint256 poolAFeePercentage,
        uint256 poolBFeePercentage,
        uint256 poolCFeePercentage
    ) public {
        _setPoolSwapFees(poolAFeePercentage, poolBFeePercentage, poolCFeePercentage);

        exactAmountIn = bound(exactAmountIn, minSwapAmountTokenA, maxSwapAmountTokenA);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender, tokensToTrack);
        uint256[] memory invariantsBefore = _getPoolInvariants();

        vm.startPrank(sender);
        uint256 amountOutDo = _executeAndCheckBatchExactIn(IERC20(address(tokenA)), exactAmountIn);
        uint256 feesTokenD = vault.getAggregateSwapFeeAmount(poolC, tokenD);
        uint256 amountOutUndo = _executeAndCheckBatchExactIn(IERC20(address(tokenD)), amountOutDo - feesTokenD);
        uint256 feesTokenA = vault.getAggregateSwapFeeAmount(poolA, tokenA);
        vm.stopPrank();

        assertTrue(feesTokenA > 0, "No fees on tokenA");
        assertTrue(feesTokenD > 0, "No fees on tokenD");

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender, tokensToTrack);
        uint256[] memory invariantsAfter = _getPoolInvariants();

        assertLe(amountOutUndo + feesTokenA, exactAmountIn, "Amount out undo should be <= exactAmountIn");

        _checkUserBalancesAndPoolInvariants(
            balancesBefore,
            balancesAfter,
            invariantsBefore,
            invariantsAfter,
            0,
            feesTokenD
        );
    }

    function testDoUndoExactOut__Fuzz(
        uint256 exactAmountOut,
        uint256 poolAFeePercentage,
        uint256 poolBFeePercentage,
        uint256 poolCFeePercentage
    ) public {
        _setPoolSwapFees(poolAFeePercentage, poolBFeePercentage, poolCFeePercentage);

        exactAmountOut = bound(exactAmountOut, minSwapAmountTokenD, maxSwapAmountTokenD);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender, tokensToTrack);
        uint256[] memory invariantsBefore = _getPoolInvariants();

        vm.startPrank(sender);
        uint256 amountInDo = _executeAndCheckBatchExactOut(IERC20(address(tokenA)), exactAmountOut);
        uint256 feesTokenA = vault.getAggregateSwapFeeAmount(poolA, tokenA);
        uint256 amountInUndo = _executeAndCheckBatchExactOut(IERC20(address(tokenD)), amountInDo + feesTokenA);
        uint256 feesTokenD = vault.getAggregateSwapFeeAmount(poolC, tokenD);
        vm.stopPrank();

        assertTrue(feesTokenA > 0, "No fees on tokenA");
        assertTrue(feesTokenD > 0, "No fees on tokenD");

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender, tokensToTrack);
        uint256[] memory invariantsAfter = _getPoolInvariants();

        assertGe(amountInUndo, exactAmountOut + feesTokenD, "Amount in undo should be >= exactAmountOut");

        _checkUserBalancesAndPoolInvariants(
            balancesBefore,
            balancesAfter,
            invariantsBefore,
            invariantsAfter,
            feesTokenA,
            0
        );
    }

    function testExactInRepeatExactOut__Fuzz(uint256 exactAmountIn, uint256 poolFeePercentage) public {
        // For this test, we need equal fees to ensure symetry between exact_in and out.
        _setPoolSwapFees(poolFeePercentage, poolFeePercentage, poolFeePercentage);

        exactAmountIn = bound(exactAmountIn, minSwapAmountTokenA, maxSwapAmountTokenA);

        vm.startPrank(sender);

        uint256 snapshotId = vm.snapshot();

        uint256 amountOut = _executeAndCheckBatchExactIn(IERC20(address(tokenA)), exactAmountIn);

        vm.revertTo(snapshotId);

        uint256 amountIn = _executeAndCheckBatchExactOut(IERC20(address(tokenA)), amountOut);

        vm.stopPrank();

        // Error tolerance is proportional to swap fee percentage.
        uint256 tolerance = bound(poolFeePercentage, 1e12, 10e16);
        assertApproxEqRel(amountIn, exactAmountIn, tolerance, "ExactIn and ExactOut amountsIn should match");
    }

    function testExactInRepeatEachOperation__Fuzz(
        uint256 exactAmountIn,
        uint256 poolAFeePercentage,
        uint256 poolBFeePercentage,
        uint256 poolCFeePercentage
    ) public {
        _setPoolSwapFees(poolAFeePercentage, poolBFeePercentage, poolCFeePercentage);

        exactAmountIn = bound(exactAmountIn, minSwapAmountTokenA, maxSwapAmountTokenA);

        vm.startPrank(sender);
        uint256 snapshotId = vm.snapshot();
        uint256 amountOutBatch = _executeAndCheckBatchExactIn(IERC20(address(tokenA)), exactAmountIn);
        vm.revertTo(snapshotId);
        uint256 amountOutEach = _executeEachOperationExactIn(exactAmountIn);
        vm.stopPrank();

        assertEq(amountOutBatch, amountOutEach, "Batch and each operation amountsOut do not match");
    }

    function testExactOutRepeatEachOperation__Fuzz(
        uint256 exactAmountOut,
        uint256 poolAFeePercentage,
        uint256 poolBFeePercentage,
        uint256 poolCFeePercentage
    ) public {
        _setPoolSwapFees(poolAFeePercentage, poolBFeePercentage, poolCFeePercentage);

        exactAmountOut = bound(exactAmountOut, minSwapAmountTokenD, maxSwapAmountTokenD);

        vm.startPrank(sender);
        uint256 snapshotId = vm.snapshot();
        uint256 amountInBatch = _executeAndCheckBatchExactOut(IERC20(address(tokenA)), exactAmountOut);
        vm.revertTo(snapshotId);
        uint256 amountInEach = _executeEachOperationExactOut(exactAmountOut);
        vm.stopPrank();

        assertEq(amountInBatch, amountInEach, "Batch and each operation amountsIn do not match");
    }

    function _executeAndCheckBatchExactIn(IERC20 tokenIn, uint256 exactAmountIn) private returns (uint256 amountOut) {
        IBatchRouter.SwapPathExactAmountIn[] memory swapPath = _buildExactInPaths(tokenIn, exactAmountIn, 0);

        (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) = batchRouter
            .swapExactIn(swapPath, MAX_UINT128, false, bytes(""));

        assertEq(pathAmountsOut.length, 1, "pathAmountsOut incorrect length");
        assertEq(tokensOut.length, 1, "tokensOut incorrect length");
        assertEq(amountsOut.length, 1, "amountsOut incorrect length");

        if (tokenIn == tokenA) {
            assertEq(tokensOut[0], address(tokenD), "tokenOut is not tokenD");
        } else {
            assertEq(tokensOut[0], address(tokenA), "tokenOut is not tokenA");
        }

        assertEq(pathAmountsOut[0], amountsOut[0], "pathAmountsOut and amountsOut do not match");

        amountOut = pathAmountsOut[0];
    }

    function _executeEachOperationExactIn(uint256 exactAmountIn) private returns (uint256 amountOut) {
        uint256 amountOutTokenB = router.swapSingleTokenExactIn(
            poolA,
            tokenA,
            tokenB,
            exactAmountIn,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 amountOutTokenC = router.swapSingleTokenExactIn(
            poolB,
            tokenB,
            tokenC,
            amountOutTokenB,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        amountOut = router.swapSingleTokenExactIn(
            poolC,
            tokenC,
            tokenD,
            amountOutTokenC,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
    }

    function _executeEachOperationExactOut(uint256 exactAmountOut) private returns (uint256 amountIn) {
        uint256 amountInTokenC = router.swapSingleTokenExactOut(
            poolC,
            tokenC,
            tokenD,
            exactAmountOut,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 amountInTokenB = router.swapSingleTokenExactOut(
            poolB,
            tokenB,
            tokenC,
            amountInTokenC,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );
        amountIn = router.swapSingleTokenExactOut(
            poolA,
            tokenA,
            tokenB,
            amountInTokenB,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );
    }

    function _executeAndCheckBatchExactOut(IERC20 tokenIn, uint256 exactAmountOut) private returns (uint256 amountIn) {
        IBatchRouter.SwapPathExactAmountOut[] memory swapPath = _buildExactOutPaths(
            tokenIn,
            MAX_UINT128,
            exactAmountOut
        );

        (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) = batchRouter
            .swapExactOut(swapPath, MAX_UINT128, false, bytes(""));

        assertEq(pathAmountsIn.length, 1, "pathAmountsIn incorrect length");
        assertEq(tokensIn.length, 1, "tokensIn incorrect length");
        assertEq(amountsIn.length, 1, "amountsIn incorrect length");

        assertEq(tokensIn[0], address(tokenIn), "tokenIn is wrong");

        assertEq(pathAmountsIn[0], amountsIn[0], "pathAmountsIn and amountsIn do not match");

        amountIn = pathAmountsIn[0];
    }

    function _checkUserBalancesAndPoolInvariants(
        BaseVaultTest.Balances memory balancesBefore,
        BaseVaultTest.Balances memory balancesAfter,
        uint256[] memory invariantsBefore,
        uint256[] memory invariantsAfter,
        uint256 feesTokenA,
        uint256 feesTokenD
    ) private view {
        // The invariants of all pools should not decrease after the batch swap operation.
        assertGe(invariantsAfter[0], invariantsBefore[0], "Wrong poolA invariant");
        assertGe(invariantsAfter[1], invariantsBefore[1], "Wrong poolB invariant");
        assertGe(invariantsAfter[2], invariantsBefore[2], "Wrong poolC invariant");

        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.

        // If feesTokenA is not 0, it means that an exact_out swap occurred and was reverted. So, an exactAmountOut of
        // tokenD was traded by an amountInTokenA. The amountInTokenA was used in another exact_out swap, but since
        // there were fees, the amountOut used was `amountInTokenA + feesTokenA`, which means that feesTokenA was added
        // to the user wallet.
        assertLe(
            balancesAfter.userTokens[tokenAIdx],
            balancesBefore.userTokens[tokenAIdx] + feesTokenA,
            "Wrong sender tokenA balance"
        );
        assertEq(
            balancesAfter.userTokens[tokenBIdx],
            balancesBefore.userTokens[tokenBIdx],
            "Wrong sender tokenB balance"
        );
        assertEq(
            balancesAfter.userTokens[tokenCIdx],
            balancesBefore.userTokens[tokenCIdx],
            "Wrong sender tokenC balance"
        );

        // If feesTokenD is not 0, it means that an exact_in swap occurred and was reverted. So, an exactAmountIn of
        // tokenA was traded by an amountOutTokenD. The amountOutTokenD was used in another exact_in swap, but since
        // there were fees, the amountIn used was `amountOutTokenD - feesTokenD`, which means that feesTokenD was added
        // in the user wallet.
        assertLe(
            balancesAfter.userTokens[tokenDIdx],
            balancesBefore.userTokens[tokenDIdx] + feesTokenD,
            "Wrong sender tokenD balance"
        );
    }

    function _buildExactInPaths(
        IERC20 tokenIn,
        uint256 exactAmountIn,
        uint256 minAmountOut
    ) private view returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenIn,
            steps: _getSwapSteps(tokenIn),
            exactAmountIn: exactAmountIn,
            minAmountOut: minAmountOut
        });
    }

    function _buildExactOutPaths(
        IERC20 tokenIn,
        uint256 maxAmountIn,
        uint256 exactAmountOut
    ) private view returns (IBatchRouter.SwapPathExactAmountOut[] memory paths) {
        paths = new IBatchRouter.SwapPathExactAmountOut[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: tokenIn,
            steps: _getSwapSteps(tokenIn),
            maxAmountIn: maxAmountIn,
            exactAmountOut: exactAmountOut
        });
    }

    function _getSwapSteps(IERC20 tokenIn) private view returns (IBatchRouter.SwapPathStep[] memory steps) {
        steps = new IBatchRouter.SwapPathStep[](3);

        if (address(tokenIn) == address(tokenD)) {
            steps[0] = IBatchRouter.SwapPathStep({ pool: poolC, tokenOut: IERC20(address(tokenC)), isBuffer: false });
            steps[1] = IBatchRouter.SwapPathStep({ pool: poolB, tokenOut: IERC20(address(tokenB)), isBuffer: false });
            steps[2] = IBatchRouter.SwapPathStep({ pool: poolA, tokenOut: IERC20(address(tokenA)), isBuffer: false });
        } else {
            steps[0] = IBatchRouter.SwapPathStep({ pool: poolA, tokenOut: IERC20(address(tokenB)), isBuffer: false });
            steps[1] = IBatchRouter.SwapPathStep({ pool: poolB, tokenOut: IERC20(address(tokenC)), isBuffer: false });
            steps[2] = IBatchRouter.SwapPathStep({ pool: poolC, tokenOut: IERC20(address(tokenD)), isBuffer: false });
        }
    }

    function _getPoolInvariants() private view returns (uint256[] memory poolInvariants) {
        address[] memory pools = [poolA, poolB, poolC].toMemoryArray();
        poolInvariants = new uint256[](pools.length);

        for (uint256 i = 0; i < pools.length; i++) {
            (, , , uint256[] memory lastBalancesLiveScaled18) = vault.getPoolTokenInfo(pools[i]);
            poolInvariants[i] = IBasePool(pools[i]).computeInvariant(lastBalancesLiveScaled18);
        }
    }

    function _setPoolSwapFees(
        uint256 poolAFeePercentage,
        uint256 poolBFeePercentage,
        uint256 poolCFeePercentage
    ) private {
        poolAFeePercentage = bound(poolAFeePercentage, 1e12, 10e16);
        poolBFeePercentage = bound(poolBFeePercentage, 1e12, 10e16);
        poolCFeePercentage = bound(poolCFeePercentage, 1e12, 10e16);

        vault.manualSetStaticSwapFeePercentage(poolA, poolAFeePercentage);
        vault.manualSetStaticSwapFeePercentage(poolB, poolBFeePercentage);
        vault.manualSetStaticSwapFeePercentage(poolC, poolCFeePercentage);
    }
}
