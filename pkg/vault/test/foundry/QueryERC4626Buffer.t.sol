// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TokenConfig, TokenType, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { RouterCommon } from "../../contracts/RouterCommon.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract QueryERC4626BufferTest is BaseVaultTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    ERC4626TestToken internal waDAI;
    ERC4626TestToken internal waUSDC;

    // For two-token pools with waDAI/waUSDC, keep track of sorted token order.
    uint256 internal waDaiIdx;
    uint256 internal waUsdcIdx;

    address internal boostedPool;

    // The boosted pool will have 100x the liquidity of the buffer
    uint256 internal boostedPoolAmount = 10e6 * 1e18;
    uint256 internal bufferAmount = boostedPoolAmount / 100;
    uint256 internal tooLargeSwapAmount = boostedPoolAmount / 2;
    // We will swap with 10% of the buffer
    uint256 internal swapAmount = bufferAmount / 10;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        waDAI = new ERC4626TestToken(dai, "Wrapped aDAI", "waDAI", 18);
        vm.label(address(waDAI), "waDAI");

        // "USDC" is deliberately 18 decimals to test one thing at a time.
        waUSDC = new ERC4626TestToken(usdc, "Wrapped aUSDC", "waUSDC", 18);
        vm.label(address(waUSDC), "waUSDC");

        (waDaiIdx, waUsdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));

        _initializeBuffers();
        _initializeBoostedPool();
        _initializeUser();
    }

    function testSwapPreconditions() public view {
        // bob should have the full boostedPool BPT.
        assertEq(IERC20(boostedPool).balanceOf(bob), boostedPoolAmount * 2 - MIN_BPT, "Wrong boosted pool BPT amount");

        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(boostedPool);
        // The boosted pool should have `boostedPoolAmount` of both tokens.
        assertEq(address(tokens[waDaiIdx]), address(waDAI), "Wrong boosted pool token (waDAI)");
        assertEq(address(tokens[waUsdcIdx]), address(waUSDC), "Wrong boosted pool token (waUSDC)");
        assertEq(balancesRaw[0], boostedPoolAmount, "Wrong boosted pool balance [0]");
        assertEq(balancesRaw[1], boostedPoolAmount, "Wrong boosted pool balance [1]");

        // LP should have correct amount of shares from buffer (invested amount in underlying minus burned "BPTs")
        assertEq(
            vault.getBufferOwnerShares(IERC20(waDAI), lp),
            bufferAmount * 2 - MIN_BPT,
            "Wrong share of waDAI buffer belonging to LP"
        );
        assertEq(
            vault.getBufferOwnerShares(IERC20(waUSDC), lp),
            bufferAmount * 2 - MIN_BPT,
            "Wrong share of waUSDC buffer belonging to LP"
        );

        // Buffer should have the correct amount of issued shares
        assertEq(vault.getBufferTotalShares(IERC20(waDAI)), bufferAmount * 2, "Wrong issued shares of waDAI buffer");
        assertEq(vault.getBufferTotalShares(IERC20(waUSDC)), bufferAmount * 2, "Wrong issued shares of waUSDC buffer");

        uint256 baseBalance;
        uint256 wrappedBalance;

        // The vault buffers should each have `bufferAmount` of their respective tokens.
        (baseBalance, wrappedBalance) = vault.getBufferBalance(IERC20(waDAI));
        assertEq(baseBalance, bufferAmount, "Wrong waDAI buffer balance for base token");
        assertEq(wrappedBalance, bufferAmount, "Wrong waDAI buffer balance for wrapped token");

        (baseBalance, wrappedBalance) = vault.getBufferBalance(IERC20(waUSDC));
        assertEq(baseBalance, bufferAmount, "Wrong waUSDC buffer balance for base token");
        assertEq(wrappedBalance, bufferAmount, "Wrong waUSDC buffer balance for wrapped token");
    }

    function testQuerySwapWithinBufferRangeExactIn() public {
        _testQuerySwapExactIn(swapAmount);
    }

    function testQuerySwapWithinBufferRangeExactOut() public {
        _testQuerySwapExactOut(swapAmount);
    }

    function testQuerySwapOutOfBufferRangeExactIn() public {
        _testQuerySwapExactIn(tooLargeSwapAmount);
    }

    function testQuerySwapOutOfBufferRangeExactOut() public {
        _testQuerySwapExactOut(tooLargeSwapAmount);
    }

    function _testQuerySwapExactIn(uint256 amount) private {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(amount);

        // Snapshots the current state of the network
        uint256 snapshotId = vm.snapshot();

        _prankStaticCall();
        // Not using staticCall because it does not allow changes in the transient storage, and reverts with
        // a StateChangeDuringStaticCall error
        (
            uint256[] memory queryPathAmountsOut,
            address[] memory queryTokensOut,
            uint256[] memory queryAmountsOut
        ) = batchRouter.querySwapExactIn(paths, bytes(""));

        // Restores the network state to snapshot
        vm.revertTo(snapshotId);

        // Executes the actual operation
        vm.prank(alice);
        (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) = batchRouter
            .swapExactIn(paths, MAX_UINT256, false, bytes(""));

        // Check if results of query and actual operations are equal
        assertEq(pathAmountsOut[0], queryPathAmountsOut[0], "pathAmountsOut's do not match");
        assertEq(tokensOut[0], queryTokensOut[0], "tokensOut's do not match");
        assertEq(amountsOut[0], queryAmountsOut[0], "amountsOut's do not match");
    }

    function _testQuerySwapExactOut(uint256 amount) private {
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(amount);

        // Snapshots the current state of the network
        uint256 snapshotId = vm.snapshot();

        _prankStaticCall();
        // Not using staticCall because it does not allow changes in the transient storage, and reverts with
        // a StateChangeDuringStaticCall error
        (
            uint256[] memory queryPathAmountsIn,
            address[] memory queryTokensIn,
            uint256[] memory queryAmountsIn
        ) = batchRouter.querySwapExactOut(paths, bytes(""));

        // Restores the network state to snapshot
        vm.revertTo(snapshotId);

        // Executes the actual operation
        vm.prank(alice);
        (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) = batchRouter
            .swapExactOut(paths, MAX_UINT256, false, bytes(""));

        // Check if results of query and actual operations are equal
        assertEq(pathAmountsIn[0], queryPathAmountsIn[0], "pathAmountsIn's do not match");
        assertEq(tokensIn[0], queryTokensIn[0], "tokensIn's do not match");
        assertEq(amountsIn[0], queryAmountsIn[0], "amountsIn's do not match");
    }

    function _buildExactInPaths(
        uint256 amount
    ) private view returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](3);
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);

        // Since this is exact in, swaps will be executed in the order given.
        // Pre-swap through DAI buffer to get waDAI, then main swap waDAI for waUSDC in the boosted pool,
        // and finally post-swap the waUSDC through the USDC buffer to calculate the USDC amount out.
        // The only token transfers are DAI in (given) and USDC out (calculated).
        steps[0] = IBatchRouter.SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });
        steps[1] = IBatchRouter.SwapPathStep({ pool: boostedPool, tokenOut: waUSDC, isBuffer: false });
        steps[2] = IBatchRouter.SwapPathStep({ pool: address(waUSDC), tokenOut: usdc, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: dai,
            steps: steps,
            exactAmountIn: amount,
            minAmountOut: amount - 1 // rebalance tests are a wei off
        });
    }

    function _buildExactOutPaths(
        uint256 amount
    ) private view returns (IBatchRouter.SwapPathExactAmountOut[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](3);
        paths = new IBatchRouter.SwapPathExactAmountOut[](1);

        // Since this is exact out, swaps will be executed in reverse order (though we submit in logical order).
        // Pre-swap through the USDC buffer to get waUSDC, then main swap waUSDC for waDAI in the boosted pool,
        // and finally post-swap the waDAI for DAI through the DAI buffer to calculate the DAI amount in.
        // The only token transfers are DAI in (calculated) and USDC out (given).
        steps[0] = IBatchRouter.SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });
        steps[1] = IBatchRouter.SwapPathStep({ pool: boostedPool, tokenOut: waUSDC, isBuffer: false });
        steps[2] = IBatchRouter.SwapPathStep({ pool: address(waUSDC), tokenOut: usdc, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: dai,
            steps: steps,
            maxAmountIn: amount,
            exactAmountOut: amount
        });
    }

    function _initializeBuffers() private {
        // Create and fund buffer pools
        vm.startPrank(lp);
        dai.mint(lp, bufferAmount);
        dai.approve(address(waDAI), bufferAmount);
        waDAI.deposit(bufferAmount, lp);

        usdc.mint(lp, bufferAmount);
        usdc.approve(address(waUSDC), bufferAmount);
        waUSDC.deposit(bufferAmount, lp);
        vm.stopPrank();

        vm.startPrank(lp);
        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);
        waUSDC.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waUSDC), address(batchRouter), type(uint160).max, type(uint48).max);

        router.addLiquidityToBuffer(waDAI, bufferAmount, bufferAmount, lp);
        router.addLiquidityToBuffer(waUSDC, bufferAmount, bufferAmount, lp);
        vm.stopPrank();
    }

    function _initializeBoostedPool() private {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[waDaiIdx].token = IERC20(waDAI);
        tokenConfig[waUsdcIdx].token = IERC20(waUSDC);
        tokenConfig[0].tokenType = TokenType.WITH_RATE;
        tokenConfig[1].tokenType = TokenType.WITH_RATE;
        tokenConfig[waDaiIdx].rateProvider = IRateProvider(address(waDAI));
        tokenConfig[waUsdcIdx].rateProvider = IRateProvider(address(waUSDC));

        PoolMock newPool = new PoolMock(IVault(address(vault)), "Boosted Pool", "BOOSTYBOI");

        factoryMock.registerTestPool(address(newPool), tokenConfig);

        vm.label(address(newPool), "boosted pool");
        boostedPool = address(newPool);

        vm.startPrank(bob);
        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);
        waUSDC.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waUSDC), address(batchRouter), type(uint160).max, type(uint48).max);

        dai.mint(bob, boostedPoolAmount);
        dai.approve(address(waDAI), boostedPoolAmount);
        waDAI.deposit(boostedPoolAmount, bob);

        usdc.mint(bob, boostedPoolAmount);
        usdc.approve(address(waUSDC), boostedPoolAmount);
        waUSDC.deposit(boostedPoolAmount, bob);

        _initPool(boostedPool, [boostedPoolAmount, boostedPoolAmount].toMemoryArray(), boostedPoolAmount * 2 - MIN_BPT);
        vm.stopPrank();
    }

    function _initializeUser() private {
        dai.mint(alice, boostedPoolAmount);
    }
}
