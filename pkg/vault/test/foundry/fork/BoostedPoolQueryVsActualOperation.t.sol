// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StablePool } from "@balancer-labs/v3-pool-stable/contracts/StablePool.sol";
import { StablePoolFactory } from "@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol";

import { ERC4626RateProvider } from "../../../contracts/test/ERC4626RateProvider.sol";
import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract BoostedPoolQueryVsActualOperationTest is BaseVaultTest {
    uint256 private constant BLOCK_NUMBER = 6288761;

    address private constant _donorDai = 0x4d02aF17A29cdA77416A1F60Eae9092BB6d9c026;
    address private constant _donorUsdc = 0x0F97F07d7473EFB5c846FB2b6c201eC1E316E994;

    IERC4626 internal constant wUSDC = IERC4626(0x8A88124522dbBF1E56352ba3DE1d9F78C143751e);
    IERC4626 internal constant wDAI = IERC4626(0xDE46e43F46ff74A23a65EBb0580cbe3dFE684a17);
    IERC20 internal usdcFork;
    IERC20 internal daiFork;

    StablePool internal boostedPool;
    StablePoolFactory internal stablePoolFactory;

    // For two-token pools with waDAI/waUSDC, keep track of sorted token order.
    uint256 internal wDaiIdx;
    uint256 internal wUsdcIdx;

    uint256 internal constant DAI_FACTOR = 1e18;
    uint256 internal constant USDC_FACTOR = 1e6;
    uint256 internal constant BUFFER_INIT_AMOUNT = 100;
    uint256 internal constant DAI_BUFFER_INIT_AMOUNT = BUFFER_INIT_AMOUNT * DAI_FACTOR;
    uint256 internal constant USDC_BUFFER_INIT_AMOUNT = BUFFER_INIT_AMOUNT * USDC_FACTOR;

    function setUp() public override {
        vm.createSelectFork({ blockNumber: BLOCK_NUMBER, urlOrAlias: "sepolia" });

        BaseVaultTest.setUp();

        _setupTokens();
        _setupLP();
        _setupBuffers();
        _createAndInitializeBoostedPool();
    }

    function testUsdcInWithinBufferExactIn__Fork__Fuzz(uint256 amountIn) public {
        amountIn = bound(amountIn, (USDC_BUFFER_INIT_AMOUNT) / 10, USDC_BUFFER_INIT_AMOUNT);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(usdcFork, amountIn, 0);

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        (uint256[] memory queryPathAmountsOut, , ) = batchRouter.querySwapExactIn(paths, bytes(""));
        vm.revertTo(snapshotId);

        vm.prank(lp);
        (uint256[] memory actualPathAmountsOut, , ) = batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        assertEq(queryPathAmountsOut[0], actualPathAmountsOut[0], "Query and actual outputs do not match");
    }

    function testUsdcInWithinBufferExactOut__Fork__Fuzz(uint256 amountOut) public {
        amountOut = bound(amountOut, (DAI_BUFFER_INIT_AMOUNT) / 10, DAI_BUFFER_INIT_AMOUNT);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            usdcFork,
            (2 * amountOut * USDC_FACTOR) / DAI_FACTOR,
            amountOut
        );

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        (uint256[] memory queryPathAmountsIn, , ) = batchRouter.querySwapExactOut(paths, bytes(""));
        vm.revertTo(snapshotId);

        vm.prank(lp);
        (uint256[] memory actualPathAmountsIn, , ) = batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        assertEq(queryPathAmountsIn[0], actualPathAmountsIn[0], "Query and actual outputs do not match");
    }

    function testUsdcInOutOfBufferExactIn__Fork__Fuzz(uint256 amountIn) public {
        amountIn = bound(amountIn, 2 * USDC_BUFFER_INIT_AMOUNT, 4 * USDC_BUFFER_INIT_AMOUNT);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(usdcFork, amountIn, 0);

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        (uint256[] memory queryPathAmountsOut, , ) = batchRouter.querySwapExactIn(paths, bytes(""));
        vm.revertTo(snapshotId);

        vm.prank(lp);
        (uint256[] memory actualPathAmountsOut, , ) = batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        assertEq(queryPathAmountsOut[0], actualPathAmountsOut[0], "Query and actual outputs do not match");
    }

    function testUsdcInOutOfBufferExactOut__Fork__Fuzz(uint256 amountOut) public {
        amountOut = bound(amountOut, 2 * DAI_BUFFER_INIT_AMOUNT, 4 * DAI_BUFFER_INIT_AMOUNT);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            usdcFork,
            (2 * amountOut * USDC_FACTOR) / DAI_FACTOR,
            amountOut
        );

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        (uint256[] memory queryPathAmountsIn, , ) = batchRouter.querySwapExactOut(paths, bytes(""));
        vm.revertTo(snapshotId);

        vm.prank(lp);
        (uint256[] memory actualPathAmountsIn, , ) = batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        assertEq(queryPathAmountsIn[0], actualPathAmountsIn[0], "Query and actual outputs do not match");
    }

    function testUsdcInBufferUnbalancedExactIn__Fork__Fuzz(
        uint256 amountIn,
        uint256 unbalancedDai,
        uint256 unbalancedUsdc
    ) public {
        unbalancedDai = bound(unbalancedDai, 0, DAI_BUFFER_INIT_AMOUNT);
        unbalancedUsdc = bound(unbalancedUsdc, 0, USDC_BUFFER_INIT_AMOUNT);
        _unbalanceBuffers(unbalancedDai, unbalancedUsdc);

        amountIn = bound(amountIn, 2 * USDC_BUFFER_INIT_AMOUNT, 4 * USDC_BUFFER_INIT_AMOUNT);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(usdcFork, amountIn, 0);

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        (uint256[] memory queryPathAmountsOut, , ) = batchRouter.querySwapExactIn(paths, bytes(""));
        vm.revertTo(snapshotId);

        vm.prank(lp);
        (uint256[] memory actualPathAmountsOut, , ) = batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        assertEq(queryPathAmountsOut[0], actualPathAmountsOut[0], "Query and actual outputs do not match");
    }

    function testUsdcInBufferUnbalancedExactOut__Fork__Fuzz(
        uint256 amountOut,
        uint256 unbalancedDai,
        uint256 unbalancedUsdc
    ) public {
        unbalancedDai = bound(unbalancedDai, 0, DAI_BUFFER_INIT_AMOUNT);
        unbalancedUsdc = bound(unbalancedUsdc, 0, USDC_BUFFER_INIT_AMOUNT);
        _unbalanceBuffers(unbalancedDai, unbalancedUsdc);

        amountOut = bound(amountOut, 2 * DAI_BUFFER_INIT_AMOUNT, 4 * DAI_BUFFER_INIT_AMOUNT);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            usdcFork,
            (2 * amountOut * USDC_FACTOR) / DAI_FACTOR,
            amountOut
        );

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        (uint256[] memory queryPathAmountsIn, , ) = batchRouter.querySwapExactOut(paths, bytes(""));
        vm.revertTo(snapshotId);

        vm.prank(lp);
        (uint256[] memory actualPathAmountsIn, , ) = batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        assertEq(queryPathAmountsIn[0], actualPathAmountsIn[0], "Query and actual outputs do not match");
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
            minAmountOut: minAmountOut // rebalance tests are a wei off
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

        if (tokenIn == daiFork) {
            steps[0] = IBatchRouter.SwapPathStep({
                pool: address(wDAI),
                tokenOut: IERC20(address(wDAI)),
                isBuffer: true
            });
            steps[1] = IBatchRouter.SwapPathStep({
                pool: address(boostedPool),
                tokenOut: IERC20(address(wUSDC)),
                isBuffer: false
            });
            steps[2] = IBatchRouter.SwapPathStep({ pool: address(wUSDC), tokenOut: usdcFork, isBuffer: true });
        } else {
            steps[0] = IBatchRouter.SwapPathStep({
                pool: address(wUSDC),
                tokenOut: IERC20(address(wUSDC)),
                isBuffer: true
            });
            steps[1] = IBatchRouter.SwapPathStep({
                pool: address(boostedPool),
                tokenOut: IERC20(address(wDAI)),
                isBuffer: false
            });
            steps[2] = IBatchRouter.SwapPathStep({ pool: address(wDAI), tokenOut: daiFork, isBuffer: true });
        }
    }

    function _unbalanceBuffers(uint256 unbalancedDai, uint256 unbalancedUsdc) private {
        if (unbalancedDai > DAI_BUFFER_INIT_AMOUNT / 2) {
            _unbalanceBuffer(WrappingDirection.WRAP, wDAI, unbalancedDai - DAI_BUFFER_INIT_AMOUNT / 2);
        } else {
            _unbalanceBuffer(WrappingDirection.UNWRAP, wDAI, DAI_BUFFER_INIT_AMOUNT / 2 - unbalancedDai);
        }

        if (unbalancedUsdc > USDC_BUFFER_INIT_AMOUNT / 2) {
            _unbalanceBuffer(WrappingDirection.WRAP, wUSDC, unbalancedUsdc - USDC_BUFFER_INIT_AMOUNT / 2);
        } else {
            _unbalanceBuffer(WrappingDirection.UNWRAP, wUSDC, USDC_BUFFER_INIT_AMOUNT / 2 - unbalancedUsdc);
        }
    }

    function _unbalanceBuffer(WrappingDirection direction, IERC4626 wToken, uint256 amountToUnbalance) private {
        if (amountToUnbalance < 1e6) {
            // If amountToUnbalance is very low, returns without unbalancing the buffer.
            return;
        }

        IERC20 tokenIn;
        IERC20 tokenOut;
        if (direction == WrappingDirection.WRAP) {
            tokenIn = IERC20(wToken.asset());
            tokenOut = IERC20(address(wToken));
        } else {
            tokenIn = IERC20(address(wToken));
            tokenOut = IERC20(wToken.asset());
        }

        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);

        steps[0] = IBatchRouter.SwapPathStep({ pool: address(wToken), tokenOut: tokenOut, isBuffer: true });

        IBatchRouter.SwapPathExactAmountIn[] memory paths = new IBatchRouter.SwapPathExactAmountIn[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenIn,
            steps: steps,
            exactAmountIn: amountToUnbalance,
            minAmountOut: 0
        });

        vm.prank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    function _setupTokens() private {
        // Label deployed wrapped tokens
        vm.label(address(wUSDC), "wUSDC");
        vm.label(address(wDAI), "wDAI");

        // Identify and label underlying tokens
        usdcFork = IERC20(wUSDC.asset());
        vm.label(address(usdcFork), "USDC");
        daiFork = IERC20(wDAI.asset());
        vm.label(address(daiFork), "DAI");

        (wDaiIdx, wUsdcIdx) = getSortedIndexes(address(wDAI), address(wUSDC));
    }

    function _setupLP() private {
        // Donate DAI to LP
        vm.prank(_donorDai);
        daiFork.transfer(lp, 10000e18);

        // Donate USDC to LP
        vm.prank(_donorUsdc);
        usdcFork.transfer(lp, 10000e6);

        vm.startPrank(lp);
        // Allow Permit2 to get tokens from LP
        usdcFork.approve(address(permit2), type(uint256).max);
        daiFork.approve(address(permit2), type(uint256).max);
        wDAI.approve(address(permit2), type(uint256).max);
        wUSDC.approve(address(permit2), type(uint256).max);
        // Allow Permit2 to move DAI and USDC from LP to Router
        permit2.approve(address(daiFork), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(usdcFork), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(wDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(wUSDC), address(router), type(uint160).max, type(uint48).max);
        // Allow Permit2 to move DAI and USDC from LP to BatchRouter
        permit2.approve(address(daiFork), address(batchRouter), type(uint160).max, type(uint48).max);
        permit2.approve(address(usdcFork), address(batchRouter), type(uint160).max, type(uint48).max);
        permit2.approve(address(wDAI), address(batchRouter), type(uint160).max, type(uint48).max);
        permit2.approve(address(wUSDC), address(batchRouter), type(uint160).max, type(uint48).max);
        // Wrap part of LP balances
        daiFork.approve(address(wDAI), 1000e18);
        wDAI.deposit(1000e18, lp);
        usdcFork.approve(address(wUSDC), 1000e6);
        wUSDC.deposit(1000e6, lp);
        vm.stopPrank();
    }

    function _setupBuffers() private {
        vm.startPrank(lp);
        router.addLiquidityToBuffer(wDAI, DAI_BUFFER_INIT_AMOUNT, wDAI.convertToShares(DAI_BUFFER_INIT_AMOUNT), lp);
        router.addLiquidityToBuffer(wUSDC, USDC_BUFFER_INIT_AMOUNT, wUSDC.convertToShares(USDC_BUFFER_INIT_AMOUNT), lp);
        vm.stopPrank();
    }

    function _createAndInitializeBoostedPool() private {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[wDaiIdx].token = IERC20(address(wDAI));
        tokenConfig[wUsdcIdx].token = IERC20(address(wUSDC));
        tokenConfig[0].tokenType = TokenType.WITH_RATE;
        tokenConfig[1].tokenType = TokenType.WITH_RATE;
        tokenConfig[wDaiIdx].rateProvider = new ERC4626RateProvider(wDAI);
        tokenConfig[wUsdcIdx].rateProvider = new ERC4626RateProvider(wUSDC);

        stablePoolFactory = new StablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");

        PoolRoleAccounts memory roleAccounts;

        address stablePool = stablePoolFactory.create(
            "Boosted Pool",
            "BP",
            tokenConfig,
            1000, // Amplification parameter used in the real boosted pool
            roleAccounts,
            1e16, // 1% swap fee, same as the real boosted pool
            address(0),
            false, // Do not accept donations
            false, // Do not disable unbalanced add/remove liquidity
            ZERO_BYTES32
        );
        vm.label(stablePool, "boosted pool");
        boostedPool = StablePool(stablePool);

        vm.startPrank(lp);
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[wDaiIdx] = 500e18;
        tokenAmounts[wUsdcIdx] = 500e6;
        _initPool(address(boostedPool), tokenAmounts, 0);
        vm.stopPrank();
    }
}
