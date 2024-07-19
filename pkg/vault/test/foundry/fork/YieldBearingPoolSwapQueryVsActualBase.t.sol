// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StablePool } from "@balancer-labs/v3-pool-stable/contracts/StablePool.sol";
import { StablePoolFactory } from "@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol";

import { ERC4626RateProvider } from "../../../contracts/test/ERC4626RateProvider.sol";
import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract YieldBearingPoolSwapQueryVsActualBase is BaseVaultTest {
    string internal network;
    uint256 internal blockNumber;

    IERC4626 internal ybToken1;
    IERC4626 internal ybToken2;
    address internal donorToken1;
    address internal donorToken2;

    IERC20 private _token1Fork;
    IERC20 private _token2Fork;

    StablePool internal yieldBearingPool;
    StablePoolFactory internal stablePoolFactory;

    // For two-token pools with waDAI/waUSDC, keep track of sorted token order.
    uint256 internal _ybToken1Idx;
    uint256 private _ybToken2Idx;

    uint256 private constant BUFFER_INIT_AMOUNT = 100;
    uint256 private constant YIELD_BEARING_POOL_INIT_AMOUNT = BUFFER_INIT_AMOUNT * 5;

    uint256 private _token1Factor;
    uint256 private _token2Factor;
    uint256 private _token1BufferInitAmount;
    uint256 private _token2BufferInitAmount;

    uint256 private _token1YieldBearingPoolInitAmount;
    uint256 private _token2YieldBearingPoolInitAmount;

    function setUp() public virtual override {
        setUpForkTestVariables();

        vm.createSelectFork({ blockNumber: blockNumber, urlOrAlias: network });

        _token1Fork = IERC20(ybToken1.asset());
        _token2Fork = IERC20(ybToken2.asset());

        (_ybToken2Idx, _ybToken1Idx) = getSortedIndexes(address(ybToken2), address(ybToken1));

        _token1Factor = 10 ** IERC20Metadata(address(_token1Fork)).decimals();
        _token2Factor = 10 ** IERC20Metadata(address(_token2Fork)).decimals();
        _token1BufferInitAmount = BUFFER_INIT_AMOUNT * _token1Factor;
        _token2BufferInitAmount = BUFFER_INIT_AMOUNT * _token2Factor;

        _token1YieldBearingPoolInitAmount = YIELD_BEARING_POOL_INIT_AMOUNT * _token1Factor;
        _token2YieldBearingPoolInitAmount = YIELD_BEARING_POOL_INIT_AMOUNT * _token2Factor;

        BaseVaultTest.setUp();

        _setupTokens();
        _setupLPAndVault();
        _setupBuffers();
        _createAndInitializeBoostedPool();
    }

    function setUpForkTestVariables() internal virtual {
        network = "sepolia";
        blockNumber = 6288761;

        ybToken1 = IERC4626(0x8A88124522dbBF1E56352ba3DE1d9F78C143751e);
        ybToken2 = IERC4626(0xDE46e43F46ff74A23a65EBb0580cbe3dFE684a17);
        donorToken1 = 0x0F97F07d7473EFB5c846FB2b6c201eC1E316E994;
        donorToken2 = 0x4d02aF17A29cdA77416A1F60Eae9092BB6d9c026;
    }

    function testWethInWithinBufferExactIn__Fork__Fuzz(uint256 amountIn) public {
        amountIn = bound(amountIn, (_token1BufferInitAmount) / 10, _token1BufferInitAmount);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(_token1Fork, amountIn, 0);

        _testExactIn(paths);
    }

    function testWethInWithinBufferExactOut__Fork__Fuzz(uint256 amountOut) public {
        amountOut = bound(amountOut, (_token2BufferInitAmount) / 10, _token2BufferInitAmount);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            _token1Fork,
            (2 * amountOut * _token1Factor) / _token2Factor,
            amountOut
        );

        _testExactOut(paths);
    }

    function testWethInOutOfBufferExactIn__Fork__Fuzz(uint256 amountIn) public {
        amountIn = bound(amountIn, 2 * _token1BufferInitAmount, 4 * _token1BufferInitAmount);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(_token1Fork, amountIn, 0);

        _testExactIn(paths);
    }

    function testWethInOutOfBufferExactOut__Fork__Fuzz(uint256 amountOut) public {
        amountOut = bound(amountOut, 2 * _token2BufferInitAmount, 4 * _token2BufferInitAmount);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            _token1Fork,
            (2 * amountOut * _token1Factor) / _token2Factor,
            amountOut
        );

        _testExactOut(paths);
    }

    function testWethInBufferUnbalancedExactIn__Fork__Fuzz(
        uint256 amountIn,
        uint256 unbalancedUsdc,
        uint256 unbalancedWeth
    ) public {
        unbalancedUsdc = bound(unbalancedUsdc, 0, _token2BufferInitAmount);
        unbalancedWeth = bound(unbalancedWeth, 0, _token1BufferInitAmount);
        _unbalanceBuffers(unbalancedUsdc, unbalancedWeth);

        amountIn = bound(amountIn, 2 * _token1BufferInitAmount, 4 * _token1BufferInitAmount);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(_token1Fork, amountIn, 0);

        _testExactIn(paths);
    }

    function testWethInBufferUnbalancedExactOut__Fork__Fuzz(
        uint256 amountOut,
        uint256 unbalancedUsdc,
        uint256 unbalancedWeth
    ) public {
        unbalancedUsdc = bound(unbalancedUsdc, 0, _token2BufferInitAmount);
        unbalancedWeth = bound(unbalancedWeth, 0, _token1BufferInitAmount);
        _unbalanceBuffers(unbalancedUsdc, unbalancedWeth);

        amountOut = bound(amountOut, 2 * _token2BufferInitAmount, 4 * _token2BufferInitAmount);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            _token1Fork,
            (2 * amountOut * _token1Factor) / _token2Factor,
            amountOut
        );

        _testExactOut(paths);
    }

    function testUsdcInWithinBufferExactIn__Fork__Fuzz(uint256 amountIn) public {
        amountIn = bound(amountIn, _token2BufferInitAmount / 10, _token2BufferInitAmount);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(_token2Fork, amountIn, 0);

        _testExactIn(paths);
    }

    function testUsdcInWithinBufferExactOut__Fork__Fuzz(uint256 amountOut) public {
        amountOut = bound(amountOut, _token1BufferInitAmount / 10, _token1BufferInitAmount);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            _token2Fork,
            (2 * amountOut * _token2Factor) / _token1Factor,
            amountOut
        );

        _testExactOut(paths);
    }

    function testUsdcInOutOfBufferExactIn__Fork__Fuzz(uint256 amountIn) public {
        amountIn = bound(amountIn, 2 * _token2BufferInitAmount, 4 * _token2BufferInitAmount);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(_token2Fork, amountIn, 0);

        _testExactIn(paths);
    }

    function testUsdcInOutOfBufferExactOut__Fork__Fuzz(uint256 amountOut) public {
        amountOut = bound(amountOut, 2 * _token1BufferInitAmount, 4 * _token1BufferInitAmount);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            _token2Fork,
            (2 * amountOut * _token2Factor) / _token1Factor,
            amountOut
        );

        _testExactOut(paths);
    }

    function testUsdcInBufferUnbalancedExactIn__Fork__Fuzz(
        uint256 amountIn,
        uint256 unbalancedUsdc,
        uint256 unbalancedWeth
    ) public {
        unbalancedUsdc = bound(unbalancedUsdc, 0, _token2BufferInitAmount);
        unbalancedWeth = bound(unbalancedWeth, 0, _token1BufferInitAmount);
        _unbalanceBuffers(unbalancedUsdc, unbalancedWeth);

        amountIn = bound(amountIn, 2 * _token2BufferInitAmount, 4 * _token2BufferInitAmount);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(_token2Fork, amountIn, 0);

        _testExactIn(paths);
    }

    function testUsdcInBufferUnbalancedExactOut__Fork__Fuzz(
        uint256 amountOut,
        uint256 unbalancedUsdc,
        uint256 unbalancedWeth
    ) public {
        unbalancedUsdc = bound(unbalancedUsdc, 0, _token2BufferInitAmount);
        unbalancedWeth = bound(unbalancedWeth, 0, _token1BufferInitAmount);
        _unbalanceBuffers(unbalancedUsdc, unbalancedWeth);

        amountOut = bound(amountOut, 2 * _token1BufferInitAmount, 4 * _token1BufferInitAmount);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            _token2Fork,
            (2 * amountOut * _token2Factor) / _token1Factor,
            amountOut
        );

        _testExactOut(paths);
    }

    function _testExactIn(IBatchRouter.SwapPathExactAmountIn[] memory paths) private {
        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        (
            uint256[] memory queryPathAmountsOut,
            address[] memory queryTokensOut,
            uint256[] memory queryAmountsOut
        ) = batchRouter.querySwapExactIn(paths, bytes(""));
        vm.revertTo(snapshotId);

        vm.prank(lp);
        (
            uint256[] memory actualPathAmountsOut,
            address[] memory actualTokensOut,
            uint256[] memory actualAmountsOut
        ) = batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        assertEq(actualPathAmountsOut.length, 1, "actualPathAmountsOut length is wrong");
        assertEq(actualTokensOut.length, 1, "actualTokensOut length is wrong");
        assertEq(actualAmountsOut.length, 1, "actualAmountsOut length is wrong");
        assertEq(
            actualPathAmountsOut.length,
            queryPathAmountsOut.length,
            "actual and query pathAmountsOut lengths do not match"
        );
        assertEq(actualTokensOut.length, queryPathAmountsOut.length, "actual and query tokensOut lengths do not match");
        assertEq(
            actualAmountsOut.length,
            queryPathAmountsOut.length,
            "actual and query amountsOut lengths do not match"
        );
        assertEq(queryPathAmountsOut[0], actualPathAmountsOut[0], "Query and actual pathAmountsOut do not match");
        assertEq(queryTokensOut[0], actualTokensOut[0], "Query and actual tokensOut do not match");
        assertEq(queryAmountsOut[0], actualAmountsOut[0], "Query and actual amountsOut do not match");
    }

    function _testExactOut(IBatchRouter.SwapPathExactAmountOut[] memory paths) private {
        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        console.log("--QUERY--");
        (
            uint256[] memory queryPathAmountsIn,
            address[] memory queryTokensIn,
            uint256[] memory queryAmountsIn
        ) = batchRouter.querySwapExactOut(paths, bytes(""));
        vm.revertTo(snapshotId);

        console.log("--ACTUAL--");

        vm.prank(lp);
        (
            uint256[] memory actualPathAmountsIn,
            address[] memory actualTokensIn,
            uint256[] memory actualAmountsIn
        ) = batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        assertEq(actualPathAmountsIn.length, 1, "actualPathAmountsIn length is wrong");
        assertEq(actualTokensIn.length, 1, "actualTokensIn length is wrong");
        assertEq(actualAmountsIn.length, 1, "actualAmountsIn length is wrong");
        assertEq(
            actualPathAmountsIn.length,
            queryPathAmountsIn.length,
            "actual and query pathAmountsIn lengths do not match"
        );
        assertEq(actualTokensIn.length, queryPathAmountsIn.length, "actual and query tokensIn lengths do not match");
        assertEq(actualAmountsIn.length, queryPathAmountsIn.length, "actual and query amountsIn lengths do not match");
        assertEq(queryPathAmountsIn[0], actualPathAmountsIn[0], "Query and actual pathAmountsIn do not match");
        assertEq(queryTokensIn[0], actualTokensIn[0], "Query and actual tokensIn do not match");
        assertEq(queryAmountsIn[0], actualAmountsIn[0], "Query and actual amountsIn do not match");
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

        if (tokenIn == _token2Fork) {
            steps[0] = IBatchRouter.SwapPathStep({
                pool: address(ybToken2),
                tokenOut: IERC20(address(ybToken2)),
                isBuffer: true
            });
            steps[1] = IBatchRouter.SwapPathStep({
                pool: address(yieldBearingPool),
                tokenOut: IERC20(address(ybToken1)),
                isBuffer: false
            });
            steps[2] = IBatchRouter.SwapPathStep({ pool: address(ybToken1), tokenOut: _token1Fork, isBuffer: true });
        } else {
            steps[0] = IBatchRouter.SwapPathStep({
                pool: address(ybToken1),
                tokenOut: IERC20(address(ybToken1)),
                isBuffer: true
            });
            steps[1] = IBatchRouter.SwapPathStep({
                pool: address(yieldBearingPool),
                tokenOut: IERC20(address(ybToken2)),
                isBuffer: false
            });
            steps[2] = IBatchRouter.SwapPathStep({ pool: address(ybToken2), tokenOut: _token2Fork, isBuffer: true });
        }
    }

    function _unbalanceBuffers(uint256 unbalancedUsdc, uint256 unbalancedWeth) private {
        if (unbalancedUsdc > _token2BufferInitAmount / 2) {
            _unbalanceBuffer(WrappingDirection.WRAP, ybToken2, unbalancedUsdc - _token2BufferInitAmount / 2);
        } else {
            _unbalanceBuffer(WrappingDirection.UNWRAP, ybToken2, _token2BufferInitAmount / 2 - unbalancedUsdc);
        }

        if (unbalancedWeth > _token1BufferInitAmount / 2) {
            _unbalanceBuffer(WrappingDirection.WRAP, ybToken1, unbalancedWeth - _token1BufferInitAmount / 2);
        } else {
            _unbalanceBuffer(WrappingDirection.UNWRAP, ybToken1, _token1BufferInitAmount / 2 - unbalancedWeth);
        }
    }

    function _unbalanceBuffer(WrappingDirection direction, IERC4626 wToken, uint256 amountToUnbalance) private {
        if (amountToUnbalance < MIN_TRADE_AMOUNT) {
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
        // Label deployed wrapped tokens.
        vm.label(address(ybToken1), "wUSDC");
        vm.label(address(ybToken2), "wDAI");

        // Identify and label underlying tokens.
        _token1Fork = IERC20(ybToken1.asset());
        vm.label(address(_token1Fork), "USDC");
        _token2Fork = IERC20(ybToken2.asset());
        vm.label(address(_token2Fork), "DAI");
    }

    function _setupLPAndVault() private {
        vm.startPrank(donorToken1);
        // Donate token1 (underlying) to LP.
        _token1Fork.transfer(lp, 100 * _token1BufferInitAmount);
        // Donate to vault, so it has enough tokens to wrap and do not preview.
        _token1Fork.transfer(lp, _token1YieldBearingPoolInitAmount);
        vm.stopPrank();

        vm.startPrank(donorToken2);
        // Donate token2 (underlying) to LP.
        _token2Fork.transfer(lp, 100 * _token2BufferInitAmount);
        // Donate to vault, so it has enough tokens to wrap and do not preview.
        _token2Fork.transfer(address(vault), _token2YieldBearingPoolInitAmount);
        vm.stopPrank();

        vm.startPrank(lp);
        // Allow Permit2 to get tokens from LP.
        _token1Fork.approve(address(permit2), type(uint256).max);
        _token2Fork.approve(address(permit2), type(uint256).max);
        ybToken2.approve(address(permit2), type(uint256).max);
        ybToken1.approve(address(permit2), type(uint256).max);
        // Allow Permit2 to move DAI and USDC from LP to Router.
        permit2.approve(address(_token2Fork), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(_token1Fork), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(ybToken2), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(ybToken1), address(router), type(uint160).max, type(uint48).max);
        // Allow Permit2 to move DAI and USDC from LP to BatchRouter.
        permit2.approve(address(_token2Fork), address(batchRouter), type(uint160).max, type(uint48).max);
        permit2.approve(address(_token1Fork), address(batchRouter), type(uint160).max, type(uint48).max);
        permit2.approve(address(ybToken2), address(batchRouter), type(uint160).max, type(uint48).max);
        permit2.approve(address(ybToken1), address(batchRouter), type(uint160).max, type(uint48).max);
        // Wrap part of LP balances.
        _token2Fork.approve(address(ybToken2), 2 * _token2YieldBearingPoolInitAmount);
        ybToken2.deposit(2 * _token2YieldBearingPoolInitAmount, lp);
        _token1Fork.approve(address(ybToken1), 2 * _token1YieldBearingPoolInitAmount);
        ybToken1.deposit(2 * _token1YieldBearingPoolInitAmount, lp);
        vm.stopPrank();
    }

    function _setupBuffers() private {
        vm.startPrank(lp);
        router.addLiquidityToBuffer(
            ybToken2,
            _token2BufferInitAmount,
            ybToken2.convertToShares(_token2BufferInitAmount),
            lp
        );
        router.addLiquidityToBuffer(
            ybToken1,
            _token1BufferInitAmount,
            ybToken1.convertToShares(_token1BufferInitAmount),
            lp
        );
        vm.stopPrank();
    }

    function _createAndInitializeBoostedPool() private {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[_ybToken2Idx].token = IERC20(address(ybToken2));
        tokenConfig[_ybToken1Idx].token = IERC20(address(ybToken1));
        tokenConfig[0].tokenType = TokenType.WITH_RATE;
        tokenConfig[1].tokenType = TokenType.WITH_RATE;
        tokenConfig[_ybToken2Idx].rateProvider = new ERC4626RateProvider(ybToken2);
        tokenConfig[_ybToken1Idx].rateProvider = new ERC4626RateProvider(ybToken1);

        stablePoolFactory = new StablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");

        PoolRoleAccounts memory roleAccounts;

        // Created copying boosted pool 0x302b75a27e5e157f93c679dd7a25fdfcdbc1473c (Sepolia).
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
        yieldBearingPool = StablePool(stablePool);

        vm.startPrank(lp);
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[_ybToken2Idx] = _token2YieldBearingPoolInitAmount;
        tokenAmounts[_ybToken1Idx] = _token1YieldBearingPoolInitAmount;
        _initPool(address(yieldBearingPool), tokenAmounts, 0);
        vm.stopPrank();
    }
}
