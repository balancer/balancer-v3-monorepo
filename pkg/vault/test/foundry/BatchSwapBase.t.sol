// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { MOCK_BATCH_ROUTER_VERSION } from "../../contracts/test/BatchRouterMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BatchSwapBaseTest is BaseVaultTest {
    using ArrayHelpers for *;
    using EnumerableSet for *;
    using EnumerableMap for *;

    uint256 constant DEFAULT_EXACT_AMOUNT_IN = 1e18;
    uint256 constant DEFAULT_MIN_AMOUNT_OUT = 1e18;
    uint256 constant ROUNDING_ERROR = 2;
    uint256 constant REMOVE_LIQUIDITY_ROUNDING_ERROR = 4000;
    uint256 tokenAmount = 1e10 * 1e18;
    uint256 wrappedTokenAmount = 1e6 * 1e18;

    address[] testPools;
    address[] testTokens;

    ERC20TestToken tokenA;
    ERC20TestToken tokenB;
    ERC20TestToken tokenC;

    ERC4626TestToken wTokenA;
    ERC4626TestToken wTokenC;

    address poolAB;
    address poolAC;
    address poolBC;

    address wTokenATokenBPool;
    address tokenBWTokenCPool;

    address nestedPoolABAC;
    address nestedPoolABBC;
    address nestedPoolACBC;

    EnumerableMap.AddressToUintMap _amountsOut;
    uint256[] _pathAmountsOut;

    EnumerableSet.AddressSet _diffTokens;
    mapping(address => int256) _vaultTokenBalancesDiff;
    mapping(address => int256) _aliceTokenBalancesDiff;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _createTokens();
        _deployPools();
    }

    function _createTokens() internal {
        // Create test tokens
        tokenA = createERC20("TokenA", 18);
        tokenB = createERC20("TokenB", 18);
        tokenC = createERC20("TokenC", 18);

        address[] memory tokens = [address(tokenA), address(tokenB), address(tokenC)].toMemoryArray();
        for (uint256 i = 0; i < users.length; ++i) {
            address user = users[i];
            vm.startPrank(user);
            for (uint256 j = 0; j < tokens.length; ++j) {
                address token = tokens[j];
                ERC20TestToken(token).mint(user, tokenAmount);

                IERC20(token).approve(address(permit2), type(uint256).max);
                permit2.approve(token, address(router), type(uint160).max, type(uint48).max);
                permit2.approve(token, address(bufferRouter), type(uint160).max, type(uint48).max);
                permit2.approve(token, address(batchRouter), type(uint160).max, type(uint48).max);
            }
            vm.stopPrank();
        }

        wTokenA = createERC4626("WrappedTokenA", "wTokenA", 18, tokenA);
        wTokenC = createERC4626("WrappedTokenC", "wTokenC", 18, tokenC);
        address[] memory erc4626Tokens = [address(wTokenA), address(wTokenC)].toMemoryArray();
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            vm.startPrank(user);
            for (uint256 j = 0; j < erc4626Tokens.length; ++j) {
                address erc4626Token = erc4626Tokens[j];

                IERC20(erc4626Token).approve(address(permit2), type(uint256).max);
                permit2.approve(erc4626Token, address(router), type(uint160).max, type(uint48).max);
                permit2.approve(erc4626Token, address(bufferRouter), type(uint160).max, type(uint48).max);
                permit2.approve(erc4626Token, address(batchRouter), type(uint160).max, type(uint48).max);

                IERC20 underlying = IERC20(ERC4626TestToken(erc4626Token).asset());
                underlying.approve(erc4626Token, type(uint160).max);

                ERC4626TestToken(erc4626Token).deposit(wrappedTokenAmount, user);

                if (user == lp) {
                    bufferRouter.initializeBuffer(ERC4626TestToken(erc4626Token), wrappedTokenAmount, 0, 0);
                }
            }

            vm.stopPrank();
        }
    }

    function _deployPools() internal {
        // Create test pools
        (poolAB, ) = _createPool([address(tokenA), address(tokenB)].toMemoryArray(), "PoolAB");
        approveForPool(IERC20(poolAB));

        (poolAC, ) = _createPool([address(tokenA), address(tokenC)].toMemoryArray(), "PoolAC");
        approveForPool(IERC20(poolAC));

        (poolBC, ) = _createPool([address(tokenB), address(tokenC)].toMemoryArray(), "PoolBC");
        approveForPool(IERC20(poolBC));

        (wTokenATokenBPool, ) = _createPool([address(wTokenA), address(tokenB)].toMemoryArray(), "wTokenATokenBPool");
        approveForPool(IERC20(wTokenATokenBPool));

        (tokenBWTokenCPool, ) = _createPool([address(tokenB), address(wTokenC)].toMemoryArray(), "tokenBWTokenCPool");
        approveForPool(IERC20(tokenBWTokenCPool));

        (nestedPoolABAC, ) = _createPool([poolAB, poolAC].toMemoryArray(), "nestedPoolFirst");
        approveForPool(IERC20(nestedPoolABAC));

        (nestedPoolABBC, ) = _createPool([poolAB, poolBC].toMemoryArray(), "nestedPoolSecond");
        approveForPool(IERC20(nestedPoolABBC));

        (nestedPoolACBC, ) = _createPool([poolAC, poolBC].toMemoryArray(), "nestedPoolThird");
        approveForPool(IERC20(nestedPoolACBC));

        vm.startPrank(lp);
        _initPool(poolAB, [poolInitAmount * 2, poolInitAmount * 2].toMemoryArray(), 0);
        _initPool(poolAC, [poolInitAmount * 2, poolInitAmount * 2].toMemoryArray(), 0);
        _initPool(poolBC, [poolInitAmount * 2, poolInitAmount * 2].toMemoryArray(), 0);

        _initPool(wTokenATokenBPool, [wrappedTokenAmount, wrappedTokenAmount].toMemoryArray(), 0);
        _initPool(tokenBWTokenCPool, [wrappedTokenAmount, wrappedTokenAmount].toMemoryArray(), 0);
        _initPool(nestedPoolABAC, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        _initPool(nestedPoolABBC, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        _initPool(nestedPoolACBC, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);

        IERC20(poolAB).transfer(alice, IERC20(poolAB).balanceOf(lp));
        IERC20(poolAC).transfer(alice, IERC20(poolAC).balanceOf(lp));
        IERC20(poolBC).transfer(alice, IERC20(poolBC).balanceOf(lp));

        vm.stopPrank();
    }

    function _queryExactIn(
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn
    ) internal returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) {
        uint256 snapshot = vm.snapshotState();

        _prankStaticCall();
        (pathAmountsOut, tokensOut, amountsOut) = batchRouter.querySwapExactIn(pathsExactIn, address(0), bytes(""));

        vm.revertToState(snapshot);
    }

    /***************************************************************************
                                    Swap Exact In
    ***************************************************************************/

    function testSwapExactInDeadline() public {
        uint256 deadline = block.timestamp - 1;

        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](0);

        vm.expectRevert(ISenderGuard.SwapDeadline.selector);
        batchRouter.swapExactIn(pathsExactIn, deadline, false, bytes(""));

        vm.expectRevert(ISenderGuard.SwapDeadline.selector);
        batchRouter.swapExactIn(pathsExactIn, deadline, true, bytes(""));
    }

    function testSwapExactInIfAmountOutLessThenMin() public {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);
        steps[0] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });

        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](1);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: steps,
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: MAX_UINT256
        });

        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, DEFAULT_EXACT_AMOUNT_IN, MAX_UINT256));
        batchRouter.swapExactIn(pathsExactIn, MAX_UINT128, false, bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, DEFAULT_EXACT_AMOUNT_IN, MAX_UINT256));
        batchRouter.swapExactIn(pathsExactIn, MAX_UINT128, true, bytes(""));

        vm.stopPrank();
    }

    function testSinglePathExactIn() public {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](2);
        steps[0] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });
        steps[1] = IBatchRouter.SwapPathStep({ pool: poolBC, tokenOut: tokenC, isBuffer: false });

        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](1);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: steps,
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });

        _testSwapExactIn(pathsExactIn, true, true);
    }

    function testSinglePathExactInIntermediateFinalSteps() public {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](5);
        steps[0] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });
        steps[1] = IBatchRouter.SwapPathStep({ pool: poolBC, tokenOut: tokenC, isBuffer: false });
        steps[2] = IBatchRouter.SwapPathStep({ pool: poolAC, tokenOut: tokenA, isBuffer: false });
        steps[3] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });
        steps[4] = IBatchRouter.SwapPathStep({ pool: poolBC, tokenOut: tokenC, isBuffer: false });

        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](1);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: steps,
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });

        _testSwapExactIn(pathsExactIn, true, true);
    }

    function testExactInMultiPathSISO() public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](2);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({ pool: poolBC, tokenOut: tokenC, isBuffer: false });

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: new IBatchRouter.SwapPathStep[](1),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[1].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAC, tokenOut: tokenC, isBuffer: false });

        _testSwapExactIn(pathsExactIn, true, true);
    }

    function testExactInMultiPathMISO() public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](2);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({ pool: poolBC, tokenOut: tokenC, isBuffer: false });

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenB,
            steps: new IBatchRouter.SwapPathStep[](1),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[1].steps[0] = IBatchRouter.SwapPathStep({ pool: poolBC, tokenOut: tokenC, isBuffer: false });

        _testSwapExactIn(pathsExactIn, true, true);
    }

    function testExactInMultiPathSIMO() public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](2);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({ pool: poolBC, tokenOut: tokenC, isBuffer: false });

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: new IBatchRouter.SwapPathStep[](1),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[1].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });

        _testSwapExactIn(pathsExactIn, true, true);
    }

    function testExactInMultiPathMIMO() public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](2);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({ pool: poolBC, tokenOut: tokenC, isBuffer: false });

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: IERC20(poolAB),
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[1].steps[0] = IBatchRouter.SwapPathStep({
            pool: nestedPoolABBC,
            tokenOut: IERC20(poolBC),
            isBuffer: false
        });
        pathsExactIn[1].steps[1] = IBatchRouter.SwapPathStep({
            pool: nestedPoolACBC,
            tokenOut: IERC20(poolAC),
            isBuffer: false
        });

        _testSwapExactIn(pathsExactIn, true, true);
    }

    function testExactInMultiPathCircular() public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](2);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({ pool: poolBC, tokenOut: tokenC, isBuffer: false });

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenC,
            steps: new IBatchRouter.SwapPathStep[](1),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[1].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAC, tokenOut: tokenA, isBuffer: false });

        _testSwapExactIn(pathsExactIn, true, true);
    }

    /***************************************************************************
                                    Add Liquidity Exact In
    ***************************************************************************/

    function testJoinSwapExactInSinglePathAndInitialAddLiquidityStep() public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](1);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT - ROUNDING_ERROR
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: poolAB,
            tokenOut: IERC20(poolAB),
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({
            pool: nestedPoolABBC,
            tokenOut: IERC20(poolBC),
            isBuffer: false
        });

        _testSwapExactIn(pathsExactIn, true, true);
    }

    function testJoinSwapExactInSinglePathAndIntermediateAddLiquidityStep() public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](1);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: new IBatchRouter.SwapPathStep[](3),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT - ROUNDING_ERROR
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({
            pool: poolBC,
            tokenOut: IERC20(poolBC),
            isBuffer: false
        });
        pathsExactIn[0].steps[2] = IBatchRouter.SwapPathStep({
            pool: nestedPoolACBC,
            tokenOut: IERC20(poolAC),
            isBuffer: false
        });

        _testSwapExactIn(pathsExactIn, true, true);
    }

    function testJoinSwapExactInMultiPathAndInitialFinalAddLiquidityStep() public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](2);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT - ROUNDING_ERROR
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: poolAB,
            tokenOut: IERC20(poolAB),
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({
            pool: nestedPoolABBC,
            tokenOut: IERC20(poolBC),
            isBuffer: false
        });

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT - ROUNDING_ERROR
        });
        pathsExactIn[1].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });
        pathsExactIn[1].steps[1] = IBatchRouter.SwapPathStep({
            pool: poolBC,
            tokenOut: IERC20(poolBC),
            isBuffer: false
        });

        _testSwapExactIn(pathsExactIn, true, true);
    }

    /***************************************************************************
                                    Remove Liquidity Exact In
    ***************************************************************************/

    function testExitSwapExactInSinglePathAndInitialRemoveLiquidityStep() public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](1);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: IERC20(poolAB),
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({ pool: poolBC, tokenOut: tokenC, isBuffer: false });

        _testSwapExactIn(pathsExactIn, true, true);
    }

    function testExitSwapExactInSinglePathAndIntermediateRemoveLiquidityStep() public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](1);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: IERC20(tokenA),
            steps: new IBatchRouter.SwapPathStep[](3),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT - REMOVE_LIQUIDITY_ROUNDING_ERROR
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: poolAB,
            tokenOut: IERC20(poolAB),
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });
        pathsExactIn[0].steps[2] = IBatchRouter.SwapPathStep({ pool: poolBC, tokenOut: tokenC, isBuffer: false });

        _testSwapExactIn(pathsExactIn, true, true);
    }

    function testExitSwapExactInSinglePathAndFinalRemoveLiquidityStep() public {
        //    baseTest.tokensIn = [baseTest.tokens.get(0)];
        //   baseTest.tokensOut = [baseTest.tokens.get(1)];
        //   baseTest.totalAmountIn = baseTest.pathExactAmountIn; // 1 path
        //   baseTest.totalAmountOut = baseTest.pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
        //   baseTest.pathAmountsOut = [baseTest.totalAmountOut]; // 1 path, all tokens out
        //   baseTest.amountsOut = [baseTest.totalAmountOut];
        //   baseTest.balanceChange = [
        //     {
        //       account: baseTest.sender,
        //       changes: {
        //         [await baseTest.tokensIn[0].symbol()]: ['very-near', -baseTest.totalAmountIn],
        //         [await baseTest.tokensOut[0].symbol()]: ['very-near', baseTest.totalAmountOut],
        //       },
        //     },
        //     {
        //       account: baseTest.vaultAddress,
        //       changes: {
        //         [await baseTest.tokensIn[0].symbol()]: ['very-near', baseTest.totalAmountIn],
        //         [await baseTest.tokensOut[0].symbol()]: ['very-near', -baseTest.totalAmountOut],
        //       },
        //     },
        //   ];
        //   baseTest.pathsExactIn = [
        //     {
        //       tokenIn: baseTest.token0,
        //       steps: [
        //         { pool: baseTest.poolA, tokenOut: baseTest.poolA, isBuffer: false },
        //         { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
        //       ],
        //       exactAmountIn: baseTest.pathExactAmountIn,
        //       minAmountOut: pct(baseTest.pathMinAmountOut, 0.999), // Rounding tolerance
        //     },
        //   ];
        // });
    }

    function testExitSwapExactInMultiPathAndFinalRemoveLiquidityStep() public {}

    function testExitSwapExactInMultiPathAndIntermediateRemoveLiquidityStep() public {}

    enum OperationType {
        WrapUnwrap,
        RemoveLiquidity,
        AddLiquidity,
        Swap
    }

    function _getOperationType(
        IBatchRouter.SwapPathStep memory step,
        IERC20 stepTokenIn
    ) internal view returns (OperationType) {
        if (step.isBuffer) {
            return OperationType.WrapUnwrap;
        } else if (address(stepTokenIn) == step.pool) {
            return OperationType.RemoveLiquidity;
        } else if (address(step.tokenOut) == step.pool) {
            return OperationType.AddLiquidity;
        } else {
            return OperationType.Swap;
        }
    }

    function _testSwapExactIn(
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn,
        bool singleTransferIn,
        bool singleTransferOut
    ) internal {
        for (uint256 i = 0; i < pathsExactIn.length; i++) {
            IBatchRouter.SwapPathExactAmountIn memory pathExactIn = pathsExactIn[i];

            uint256 lastStepIndex = pathExactIn.steps.length - 1;
            IERC20 stepTokenIn = lastStepIndex == 0
                ? pathExactIn.tokenIn
                : pathExactIn.steps[lastStepIndex - 1].tokenOut;

            IBatchRouter.SwapPathStep memory firstStep = pathExactIn.steps[0];
            IBatchRouter.SwapPathStep memory lastStep = pathExactIn.steps[pathExactIn.steps.length - 1];

            OperationType lastOperationType = _getOperationType(lastStep, stepTokenIn);
            OperationType firstOperationType = _getOperationType(firstStep, pathExactIn.tokenIn);

            if (firstOperationType == OperationType.RemoveLiquidity) {
                _aliceTokenBalancesDiff[address(pathExactIn.tokenIn)] -= int256(pathExactIn.exactAmountIn);
            } else {
                _vaultTokenBalancesDiff[address(pathExactIn.tokenIn)] += int256(pathExactIn.exactAmountIn);
                _aliceTokenBalancesDiff[address(pathExactIn.tokenIn)] -= int256(pathExactIn.exactAmountIn);
            }

            if (lastOperationType == OperationType.AddLiquidity) {
                _aliceTokenBalancesDiff[address(lastStep.tokenOut)] += int256(pathExactIn.minAmountOut);
            } else {
                _vaultTokenBalancesDiff[address(lastStep.tokenOut)] -= int256(pathExactIn.minAmountOut);

                _aliceTokenBalancesDiff[address(lastStep.tokenOut)] += int256(pathExactIn.minAmountOut);
            }

            _diffTokens.add(address(pathExactIn.tokenIn));
            _diffTokens.add(address(lastStep.tokenOut));

            (, uint256 currentAmountOut) = _amountsOut.tryGet(address(lastStep.tokenOut));
            _amountsOut.set(address(lastStep.tokenOut), currentAmountOut + pathExactIn.minAmountOut);

            _pathAmountsOut.push(pathExactIn.minAmountOut);
        }

        address[] memory _diffTokensArray = _diffTokens.values();
        uint256[] memory vaultTokenBalancesBefore = new uint256[](_diffTokensArray.length);
        uint256[] memory aliceTokenBalancesBefore = new uint256[](_diffTokensArray.length);
        for (uint256 i = 0; i < _diffTokensArray.length; i++) {
            vaultTokenBalancesBefore[i] = IERC20(_diffTokensArray[i]).balanceOf(address(vault));
            aliceTokenBalancesBefore[i] = IERC20(_diffTokensArray[i]).balanceOf(alice);
        }

        // for (uint256 i = 0; i < pathsExactIn.length; i++) {
        //     if (singleTransferIn) {
        //         vm.expectEmit();
        //         emit IERC20.Transfer(alice, address(vault), _totalAmountsIn[address(pathsExactIn.tokenIn)]);
        //     }

        //     if (singleTransferOut) {
        //         uint256 lastStepIndex = pathsExactIn.steps.length - 1;
        //         IBatchRouter.SwapPathStep memory lastStep = pathsExactIn.steps[lastStepIndex];

        //         vm.expectEmit();
        //         emit IERC20.Transfer(address(vault), alice, _totalAmountsOut[address(lastStep.tokenOut)]);
        //     }
        // }

        (
            uint256[] memory queryCalculatedPathAmountsOut,
            address[] memory queryTokensOut,
            uint256[] memory queryAmountsOut
        ) = _queryExactIn(pathsExactIn);

        vm.prank(alice);
        (
            uint256[] memory calculatedPathAmountsOut,
            address[] memory tokensOut,
            uint256[] memory amountsOut
        ) = batchRouter.swapExactIn(pathsExactIn, MAX_UINT256, false, bytes(""));

        for (uint256 i = 0; i < _diffTokensArray.length; i++) {
            console.log("token", _diffTokensArray[i]);
            console.log("diff", _vaultTokenBalancesDiff[_diffTokensArray[i]]);
            assertApproxEqAbs(
                int256(IERC20(_diffTokensArray[i]).balanceOf(address(vault))),
                int256(vaultTokenBalancesBefore[i]) + int256(_vaultTokenBalancesDiff[_diffTokensArray[i]]),
                0, //TODO
                "vault token balance mismatch"
            );
            assertApproxEqAbs(
                int256(IERC20(_diffTokensArray[i]).balanceOf(alice)),
                int256(aliceTokenBalancesBefore[i]) + int256(_aliceTokenBalancesDiff[_diffTokensArray[i]]),
                0, //TODO
                "alice token balance mismatch"
            );
        }

        assertEq(calculatedPathAmountsOut.length, _pathAmountsOut.length, "expected path amounts out length mismatch");
        assertEq(tokensOut.length, _amountsOut.length(), "expected tokens out length mismatch");
        assertEq(queryAmountsOut.length, _amountsOut.length(), "expected amounts out length mismatch");

        assertEq(
            queryCalculatedPathAmountsOut.length,
            calculatedPathAmountsOut.length,
            "query path amounts out length mismatch"
        );
        assertEq(queryTokensOut.length, tokensOut.length, "query tokens out length mismatch");
        assertEq(queryAmountsOut.length, amountsOut.length, "query amounts out length mismatch");

        for (uint256 i = 0; i < calculatedPathAmountsOut.length; i++) {
            assertApproxEqAbs(
                calculatedPathAmountsOut[i],
                _pathAmountsOut[i],
                1e8,
                "expected path amounts out different than actual"
            );

            assertEq(
                calculatedPathAmountsOut[i],
                queryCalculatedPathAmountsOut[i],
                "query expected path amounts out different than actual"
            );
        }

        for (uint256 i = 0; i < tokensOut.length; i++) {
            assertApproxEqAbs(
                amountsOut[i],
                _amountsOut.get(tokensOut[i]),
                1e8,
                "expected amounts out different than actual"
            );

            assertEq(tokensOut[i], queryTokensOut[i], "query expected tokens out different than actual");
            assertEq(amountsOut[i], queryAmountsOut[i], "query expected amounts out different than actual");
        }
    }
}
