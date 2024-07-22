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

abstract contract YieldBearingPoolSwapBase is BaseVaultTest {
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

    function setUpForkTestVariables() internal virtual;

    function testSwapPreconditions__Fork() public view {
        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(yieldBearingPool));
        // The yield-bearing pool should have `boostedPoolAmount` of both tokens.
        assertEq(address(tokens[_ybToken1Idx]), address(ybToken1), "Wrong yield-bearing pool token (ybToken1)");
        assertEq(address(tokens[_ybToken2Idx]), address(ybToken2), "Wrong yield-bearing pool token (ybToken2)");

        uint256 yieldBearingPoolAmountToken1 = ybToken1.convertToShares(_token1YieldBearingPoolInitAmount);
        uint256 yieldBeraingPoolAmountToken2 = ybToken2.convertToShares(_token2YieldBearingPoolInitAmount);

        assertEq(
            balancesRaw[_ybToken1Idx],
            yieldBearingPoolAmountToken1,
            "Wrong yield-bearing pool balance [ybToken1]"
        );
        assertEq(
            balancesRaw[_ybToken2Idx],
            yieldBeraingPoolAmountToken2,
            "Wrong yield-bearing pool balance [ybToken2]"
        );

        // LP should have correct amount of shares from buffer (invested amount in underlying minus burned "BPTs")
        assertApproxEqAbs(
            vault.getBufferOwnerShares(IERC20(ybToken1), lp),
            _token1BufferInitAmount * 2 - MIN_BPT,
            1,
            "Wrong share of ybToken1 buffer belonging to LP"
        );
        assertApproxEqAbs(
            vault.getBufferOwnerShares(IERC20(ybToken2), lp),
            (_token2BufferInitAmount * 2) - MIN_BPT,
            1,
            "Wrong share of ybToken2 buffer belonging to LP"
        );

        // Buffer should have the correct amount of issued shares
        assertApproxEqAbs(
            vault.getBufferTotalShares(IERC20(ybToken1)),
            _token1BufferInitAmount * 2,
            1,
            "Wrong issued shares of ybToken1 buffer"
        );
        assertApproxEqAbs(
            vault.getBufferTotalShares(IERC20(ybToken2)),
            (_token2BufferInitAmount * 2),
            1,
            "Wrong issued shares of ybToken2 buffer"
        );

        uint256 underlyingBalance;
        uint256 wrappedBalance;

        // The vault buffers should each have `bufferAmount` of their respective tokens.
        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(IERC20(ybToken1));
        assertEq(underlyingBalance, _token1BufferInitAmount, "Wrong ybToken1 buffer balance for underlying token");
        assertEq(
            wrappedBalance,
            ybToken1.convertToShares(_token1BufferInitAmount),
            "Wrong ybToken1 buffer balance for wrapped token"
        );

        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(IERC20(ybToken2));
        assertEq(underlyingBalance, _token2BufferInitAmount, "Wrong ybToken2 buffer balance for underlying token");
        assertEq(
            wrappedBalance,
            ybToken2.convertToShares(_token2BufferInitAmount),
            "Wrong ybToken2 buffer balance for wrapped token"
        );
    }

    function testToken1InToken2OutWithinBufferExactIn__Fork__Fuzz(uint256 amountIn) public {
        amountIn = bound(amountIn, (_token1BufferInitAmount) / 10, _token1BufferInitAmount);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(_token1Fork, amountIn, 0);

        _testExactIn(paths);
    }

    function testToken1InToken2OutWithinBufferExactOut__Fork__Fuzz(uint256 amountOut) public {
        amountOut = bound(amountOut, (_token2BufferInitAmount) / 10, _token2BufferInitAmount);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            _token1Fork,
            (2 * amountOut * _token1Factor) / _token2Factor,
            amountOut
        );

        _testExactOut(paths);
    }

    function testToken1InToken2OutOutOfBufferExactIn__Fork__Fuzz(uint256 amountIn) public {
        amountIn = bound(amountIn, 2 * _token1BufferInitAmount, 4 * _token1BufferInitAmount);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(_token1Fork, amountIn, 0);

        _testExactIn(paths);
    }

    function testToken1InToken2OutOutOfBufferExactOut__Fork__Fuzz(uint256 amountOut) public {
        amountOut = bound(amountOut, 2 * _token2BufferInitAmount, 4 * _token2BufferInitAmount);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            _token1Fork,
            (2 * amountOut * _token1Factor) / _token2Factor,
            amountOut
        );

        _testExactOut(paths);
    }

    function testToken1InToken2OutBufferUnbalancedExactIn__Fork__Fuzz(
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

    function testToken1InToken2OutBufferUnbalancedExactOut__Fork__Fuzz(
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

    function testToken2InToken1OutWithinBufferExactIn__Fork__Fuzz(uint256 amountIn) public {
        amountIn = bound(amountIn, _token2BufferInitAmount / 10, _token2BufferInitAmount);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(_token2Fork, amountIn, 0);

        _testExactIn(paths);
    }

    function testToken2InToken1OutWithinBufferExactOut__Fork__Fuzz(uint256 amountOut) public {
        amountOut = bound(amountOut, _token1BufferInitAmount / 10, _token1BufferInitAmount);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            _token2Fork,
            (2 * amountOut * _token2Factor) / _token1Factor,
            amountOut
        );

        _testExactOut(paths);
    }

    function testToken2InToken1OutOutOfBufferExactIn__Fork__Fuzz(uint256 amountIn) public {
        amountIn = bound(amountIn, 2 * _token2BufferInitAmount, 4 * _token2BufferInitAmount);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(_token2Fork, amountIn, 0);

        _testExactIn(paths);
    }

    function testToken2InToken1OutOutOfBufferExactOut__Fork__Fuzz(uint256 amountOut) public {
        amountOut = bound(amountOut, 2 * _token1BufferInitAmount, 4 * _token1BufferInitAmount);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            _token2Fork,
            (2 * amountOut * _token2Factor) / _token1Factor,
            amountOut
        );

        _testExactOut(paths);
    }

    function testToken2InToken1OutBufferUnbalancedExactIn__Fork__Fuzz(
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

    function testToken2InToken1OutBufferUnbalancedExactOut__Fork__Fuzz(
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

        // Measure tokens before actual swap
        SwapResultLocals memory vars = _createSwapResultLocals(
            SwapKind.EXACT_IN,
            IERC4626(address(paths[0].steps[0].tokenOut)),
            IERC4626(address(paths[0].steps[1].tokenOut))
        );

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
        (
            uint256[] memory queryPathAmountsIn,
            address[] memory queryTokensIn,
            uint256[] memory queryAmountsIn
        ) = batchRouter.querySwapExactOut(paths, bytes(""));
        vm.revertTo(snapshotId);

        // Measure tokens before actual swap
        SwapResultLocals memory vars = _createSwapResultLocals(
            SwapKind.EXACT_IN,
            IERC4626(address(paths[0].steps[0].tokenOut)),
            IERC4626(address(paths[0].steps[1].tokenOut))
        );
        //        vars.expectedDeltaToken1 = paths[0].exactAmountOut;
        //        vars.expectedBufferDeltaToken1 = int256(paths[0].exactAmountOut);
        //        vars.expectedDeltaToken2 = swapAmount / USDC_FACTOR;
        //        vars.expectedBufferDeltaToken2 = -int256(swapAmount / USDC_FACTOR);

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

        // Created copying yield-bearing pool 0x302b75a27e5e157f93c679dd7a25fdfcdbc1473c (Sepolia).
        address stablePool = stablePoolFactory.create(
            "Boosted Pool",
            "BP",
            tokenConfig,
            1000, // Amplification parameter used in the real yield-bearing pool
            roleAccounts,
            1e16, // 1% swap fee, same as the real yield-bearing pool
            address(0),
            false, // Do not accept donations
            false, // Do not disable unbalanced add/remove liquidity
            ZERO_BYTES32
        );
        vm.label(stablePool, "yield-bearing pool");
        yieldBearingPool = StablePool(stablePool);

        vm.startPrank(lp);
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[_ybToken1Idx] = ybToken1.convertToShares(_token1YieldBearingPoolInitAmount);
        tokenAmounts[_ybToken2Idx] = ybToken2.convertToShares(_token2YieldBearingPoolInitAmount);
        _initPool(address(yieldBearingPool), tokenAmounts, 0);
        vm.stopPrank();
    }

    struct SwapResultLocals {
        SwapKind kind;
        IERC20 tokenIn;
        IERC20 tokenOut;
        IERC20 ybTokenIn;
        IERC20 ybTokenOut;
        uint256 indexYbTokenIn;
        uint256 indexYbTokenOut;
        uint256 lpBeforeSwapTokenIn;
        uint256 lpBeforeSwapTokenOut;
        uint256 bufferBeforeSwapTokenIn;
        uint256 bufferBeforeSwapYbTokenIn;
        uint256 bufferBeforeSwapTokenOut;
        uint256 bufferBeforeSwapYbTokenOut;
        uint256 poolBeforeSwapYbTokenIn;
        uint256 poolBeforeSwapYbTokenOut;
        uint256 expectedDeltaTokenIn;
        uint256 expectedDeltaTokenOut;
        int256 expectedBufferDeltaTokenIn;
        int256 expectedBufferDeltaTokenOut;
    }

    function _createSwapResultLocals(
        SwapKind kind,
        IERC4626 ybTokenIn,
        IERC4626 ybTokenOut
    ) private view returns (SwapResultLocals memory vars) {
        vars.kind = kind;

        vars.tokenIn = IERC4626(ybTokenIn.asset());
        vars.tokenOut = IERC4626(ybTokenOut.asset());

        vars.lpBeforeSwapTokenIn = vars.tokenIn.balanceOf(lp);
        vars.lpBeforeSwapTokenOut = vars.tokenOut.balanceOf(lp);

        uint256 underlyingBalance;
        uint256 wrappedBalance;
        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(IERC20(address(ybTokenIn)));
        vars.bufferBeforeSwapTokenIn = underlyingBalance;
        vars.bufferBeforeSwapYbTokenIn = wrappedBalance;
        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(IERC20(address(ybTokenOut)));
        vars.bufferBeforeSwapTokenOut = underlyingBalance;
        vars.bufferBeforeSwapYbTokenOut = wrappedBalance;

        uint256[] memory balancesRaw;
        (, , balancesRaw, ) = vault.getPoolTokenInfo(address(yieldBearingPool));
        if (vars.tokenIn == _token1Fork) {
            vars.indexYbTokenIn = _ybToken1Idx;
            vars.indexYbTokenOut = _ybToken2Idx;
        } else {
            vars.indexYbTokenIn = _ybToken2Idx;
            vars.indexYbTokenOut = _ybToken1Idx;
        }
        vars.poolBeforeSwapYbTokenIn = balancesRaw[vars.indexYbTokenIn];
        vars.poolBeforeSwapYbTokenOut = balancesRaw[vars.indexYbTokenOut];
    }

    function _verifySwapResult(
        uint256[] memory paths,
        address[] memory tokens,
        uint256[] memory amounts,
        SwapResultLocals memory vars
    ) private view {
        assertEq(paths.length, 1, "Incorrect output array length");

        assertEq(paths.length, tokens.length, "Output array length mismatch");
        assertEq(tokens.length, amounts.length, "Output array length mismatch");

        // Check results
        if (vars.kind == SwapKind.EXACT_IN) {
            // Rounding issues occurs in favor of vault, and are very small
            assertLe(paths[0], vars.expectedDeltaTokenOut, "paths AmountOut must be <= expected amountOut");
            assertApproxEqAbs(paths[0], vars.expectedDeltaTokenOut, 2, "Wrong path count");
            assertLe(paths[0], vars.expectedDeltaTokenOut, "amounts AmountOut must be <= expected amountOut");
            assertApproxEqAbs(amounts[0], vars.expectedDeltaTokenOut, 2, "Wrong amounts count");
            assertEq(tokens[0], address(vars.tokenOut), "Wrong token for SwapKind");
        } else {
            // Rounding issues occurs in favor of vault, and are very small
            assertGe(paths[0], vars.expectedDeltaTokenIn, "paths AmountIn must be >= expected amountIn");
            assertApproxEqAbs(paths[0], vars.expectedDeltaTokenIn, 5, "Wrong path count");
            assertGe(amounts[0], vars.expectedDeltaTokenIn, "amounts AmountIn must be >= expected amountIn");
            assertApproxEqAbs(amounts[0], vars.expectedDeltaTokenIn, 5, "Wrong amounts count");
            assertEq(tokens[0], address(vars.tokenIn), "Wrong token for SwapKind");
        }

        // Tokens were transferred
        assertLe(
            vars.tokenIn.balanceOf(alice),
            vars.lpBeforeSwapTokenIn - vars.expectedDeltaTokenIn,
            "Alice balance tokenIn must be <= expected balance"
        );
        assertApproxEqAbs(
            vars.tokenIn.balanceOf(alice),
            vars.lpBeforeSwapTokenIn - vars.expectedDeltaTokenIn,
            5,
            "Wrong ending balance of tokenIn for Alice"
        );
        assertLe(
            vars.tokenOut.balanceOf(alice),
            vars.lpBeforeSwapTokenOut + vars.expectedDeltaTokenOut,
            "Alice balance tokenOut must be <= expected balance"
        );
        assertApproxEqAbs(
            vars.tokenOut.balanceOf(alice),
            vars.lpBeforeSwapTokenOut + vars.expectedDeltaTokenOut,
            5,
            "Wrong ending balance of tokenOut for Alice"
        );

        uint256[] memory balancesRaw;

        (, , balancesRaw, ) = vault.getPoolTokenInfo(address(yieldBearingPool));
        assertApproxEqAbs(
            balancesRaw[vars.indexYbTokenIn],
            vars.poolBeforeSwapYbTokenIn + IERC4626(address(vars.ybTokenIn)).convertToShares(vars.expectedDeltaTokenIn),
            5,
            "Wrong yield-bearing pool tokenIn balance"
        );
        assertApproxEqAbs(
            balancesRaw[vars.indexYbTokenOut],
            vars.poolBeforeSwapYbTokenOut -
                IERC4626(address(vars.ybTokenOut)).convertToShares(vars.expectedDeltaTokenOut),
            2,
            "Wrong yield-bearing pool tokenOut balance"
        );

        uint256 underlyingBalance;
        uint256 wrappedBalance;
        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(vars.ybTokenIn);
        assertApproxEqAbs(
            underlyingBalance,
            uint256(int256(vars.bufferBeforeSwapTokenIn) + vars.expectedBufferDeltaTokenIn),
            5,
            "Wrong tokenIn buffer pool underlying balance"
        );
        assertApproxEqAbs(
            wrappedBalance,
            uint256(
                int256(vars.bufferBeforeSwapYbTokenIn) +
                    (
                        vars.expectedBufferDeltaTokenIn < int256(0)
                            ? int256(
                                IERC4626(address(vars.ybTokenIn)).convertToShares(
                                    uint256(-vars.expectedBufferDeltaTokenIn)
                                )
                            )
                            : -int256(
                                IERC4626(address(vars.ybTokenIn)).convertToShares(
                                    uint256(vars.expectedBufferDeltaTokenIn)
                                )
                            )
                    )
            ),
            5,
            "Wrong tokenIn buffer pool wrapped balance"
        );

        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(vars.ybTokenOut);
        assertApproxEqAbs(
            underlyingBalance,
            uint256(int256(vars.bufferBeforeSwapTokenOut) + vars.expectedBufferDeltaTokenOut),
            5,
            "Wrong tokenOut buffer pool underlying balance"
        );
        assertApproxEqAbs(
            wrappedBalance,
            uint256(
                int256(vars.bufferBeforeSwapYbTokenOut) +
                    (
                        vars.expectedBufferDeltaTokenOut < int256(0)
                            ? int256(
                                IERC4626(address(vars.ybTokenOut)).convertToShares(
                                    uint256(-vars.expectedBufferDeltaTokenOut)
                                )
                            )
                            : -int256(
                                IERC4626(address(vars.ybTokenOut)).convertToShares(
                                    uint256(vars.expectedBufferDeltaTokenOut)
                                )
                            )
                    )
            ),
            5,
            "Wrong tokenOut buffer pool wrapped balance"
        );
    }
}
