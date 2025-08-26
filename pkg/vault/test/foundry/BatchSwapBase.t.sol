// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

    uint256 constant DEFAULT_PATH_EXACT_AMOUNT_IN = 1e18;
    uint256 constant DEFAULT_PATH_MIN_AMOUNT_OUT = 1e18;
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

    mapping(address => uint256) _tokenOutIndex;
    address[] _tokensOut;
    uint256[] _pathAmountsOut;
    uint256[] _amountsOut;

    address[] _diffTokens;
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
            exactAmountIn: DEFAULT_PATH_EXACT_AMOUNT_IN,
            minAmountOut: MAX_UINT256
        });

        vm.startPrank(alice);

        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, DEFAULT_PATH_EXACT_AMOUNT_IN, MAX_UINT256)
        );
        batchRouter.swapExactIn(pathsExactIn, MAX_UINT128, false, bytes(""));

        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, DEFAULT_PATH_EXACT_AMOUNT_IN, MAX_UINT256)
        );
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
            exactAmountIn: DEFAULT_PATH_EXACT_AMOUNT_IN,
            minAmountOut: 0
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
            exactAmountIn: DEFAULT_PATH_EXACT_AMOUNT_IN,
            minAmountOut: 0
        });

        _testSwapExactIn(pathsExactIn, true, true);
    }

    function testExactInMultiPathSISO() public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](2);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_PATH_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_PATH_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({ pool: poolBC, tokenOut: tokenC, isBuffer: false });

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: new IBatchRouter.SwapPathStep[](1),
            exactAmountIn: DEFAULT_PATH_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_PATH_MIN_AMOUNT_OUT
        });
        pathsExactIn[1].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAC, tokenOut: tokenC, isBuffer: false });

        _testSwapExactIn(pathsExactIn, true, true);
    }

    function testExactInMultiPathMISO() public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](2);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_PATH_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_PATH_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({ pool: poolBC, tokenOut: tokenC, isBuffer: false });

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenB,
            steps: new IBatchRouter.SwapPathStep[](1),
            exactAmountIn: DEFAULT_PATH_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_PATH_MIN_AMOUNT_OUT
        });
        pathsExactIn[1].steps[0] = IBatchRouter.SwapPathStep({ pool: poolBC, tokenOut: tokenC, isBuffer: false });

        _testSwapExactIn(pathsExactIn, true, true);
    }

    function testExactInMultiPathSIMO() public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](2);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_PATH_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_PATH_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({ pool: poolBC, tokenOut: tokenC, isBuffer: false });

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: new IBatchRouter.SwapPathStep[](1),
            exactAmountIn: DEFAULT_PATH_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_PATH_MIN_AMOUNT_OUT
        });
        pathsExactIn[1].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });

        _testSwapExactIn(pathsExactIn, true, true);
    }

    function testExactInMultiPathMIMO() public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](2);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenA,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_PATH_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_PATH_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({ pool: poolBC, tokenOut: tokenC, isBuffer: false });

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: IERC20(poolAB),
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_PATH_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_PATH_MIN_AMOUNT_OUT
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
            exactAmountIn: DEFAULT_PATH_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_PATH_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAB, tokenOut: tokenB, isBuffer: false });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({ pool: poolBC, tokenOut: tokenC, isBuffer: false });

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenC,
            steps: new IBatchRouter.SwapPathStep[](1),
            exactAmountIn: DEFAULT_PATH_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_PATH_MIN_AMOUNT_OUT
        });
        pathsExactIn[1].steps[0] = IBatchRouter.SwapPathStep({ pool: poolAC, tokenOut: tokenA, isBuffer: false });

        _testSwapExactIn(pathsExactIn, true, true);
    }

    function _testSwapExactIn(
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn,
        bool singleTransferIn,
        bool singleTransferOut
    ) internal {
        for (uint256 i = 0; i < pathsExactIn.length; i++) {
            uint256 lastStepIndex = pathsExactIn[i].steps.length - 1;
            IBatchRouter.SwapPathStep memory lastStep = pathsExactIn[i].steps[lastStepIndex];

            if (_tokenOutIndex[address(lastStep.tokenOut)] == 0) {
                _tokenOutIndex[address(lastStep.tokenOut)] = _tokensOut.length + 1;
                _tokensOut.push(address(lastStep.tokenOut));
                _amountsOut.push(DEFAULT_PATH_MIN_AMOUNT_OUT);
            } else {
                _amountsOut[_tokenOutIndex[address(lastStep.tokenOut)] - 1] += DEFAULT_PATH_MIN_AMOUNT_OUT;
            }

            _pathAmountsOut.push(DEFAULT_PATH_MIN_AMOUNT_OUT);

            _diffTokens.push(address(lastStep.tokenOut));
            _diffTokens.push(address(pathsExactIn[i].tokenIn));

            _vaultTokenBalancesDiff[address(pathsExactIn[i].tokenIn)] += int256(DEFAULT_PATH_EXACT_AMOUNT_IN);
            _vaultTokenBalancesDiff[address(pathsExactIn[i].steps[lastStepIndex].tokenOut)] -= int256(
                DEFAULT_PATH_MIN_AMOUNT_OUT
            );

            _aliceTokenBalancesDiff[address(pathsExactIn[i].tokenIn)] -= int256(DEFAULT_PATH_EXACT_AMOUNT_IN);
            _aliceTokenBalancesDiff[address(pathsExactIn[i].steps[lastStepIndex].tokenOut)] += int256(
                DEFAULT_PATH_MIN_AMOUNT_OUT
            );
        }

        uint256[] memory vaultTokenBalancesBefore = new uint256[](_diffTokens.length);
        uint256[] memory aliceTokenBalancesBefore = new uint256[](_diffTokens.length);
        for (uint256 i = 0; i < _diffTokens.length; i++) {
            vaultTokenBalancesBefore[i] = IERC20(_diffTokens[i]).balanceOf(address(vault));
            aliceTokenBalancesBefore[i] = IERC20(_diffTokens[i]).balanceOf(alice);
        }

        // for (uint256 i = 0; i < pathsExactIn.length; i++) {
        //     if (singleTransferIn) {
        //         vm.expectEmit();
        //         emit IERC20.Transfer(alice, address(vault), _totalAmountsIn[address(pathsExactIn[i].tokenIn)]);
        //     }

        //     if (singleTransferOut) {
        //         uint256 lastStepIndex = pathsExactIn[i].steps.length - 1;
        //         IBatchRouter.SwapPathStep memory lastStep = pathsExactIn[i].steps[lastStepIndex];

        //         vm.expectEmit();
        //         emit IERC20.Transfer(address(vault), alice, _totalAmountsOut[address(lastStep.tokenOut)]);
        //     }
        // }

        vm.prank(alice);
        (
            uint256[] memory calculatedPathAmountsOut,
            address[] memory tokensOut,
            uint256[] memory amountsOut
        ) = batchRouter.swapExactIn(pathsExactIn, MAX_UINT256, false, bytes(""));

        for (uint256 i = 0; i < _diffTokens.length; i++) {
            assertApproxEqAbs(
                int256(IERC20(_diffTokens[i]).balanceOf(address(vault))),
                int256(vaultTokenBalancesBefore[i]) + int256(_vaultTokenBalancesDiff[_diffTokens[i]]),
                0, //TODO
                "vault token balance mismatch"
            );
            assertApproxEqAbs(
                int256(IERC20(_diffTokens[i]).balanceOf(alice)),
                int256(aliceTokenBalancesBefore[i]) + int256(_aliceTokenBalancesDiff[_diffTokens[i]]),
                0, //TODO
                "alice token balance mismatch"
            );
        }

        (
            uint256[] memory queryCalculatedPathAmountsOut,
            address[] memory queryTokensOut,
            uint256[] memory queryAmountsOut
        ) = _queryExactIn(pathsExactIn);

        assertEq(calculatedPathAmountsOut.length, _pathAmountsOut.length, "expected path amounts out length mismatch");
        assertEq(tokensOut.length, _tokensOut.length, "expected tokens out length mismatch");
        assertEq(queryAmountsOut.length, _amountsOut.length, "expected amounts out length mismatch");

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

        for (uint256 i = 0; i < _tokensOut.length; i++) {
            assertEq(tokensOut[i], _tokensOut[i], "expected tokens out different than actual");
            assertApproxEqAbs(amountsOut[i], _amountsOut[i], 1e8, "expected amounts out different than actual");

            assertEq(tokensOut[i], queryTokensOut[i], "query expected tokens out different than actual");
            assertEq(amountsOut[i], queryAmountsOut[i], "query expected amounts out different than actual");
        }
    }
}
