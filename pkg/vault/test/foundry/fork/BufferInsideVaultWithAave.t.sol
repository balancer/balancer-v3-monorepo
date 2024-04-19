// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { TokenConfig, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { ERC4626BufferPoolFactoryMock } from "../utils/ERC4626BufferPoolFactoryMock.sol";
import { ERC4626BufferPoolMock } from "../utils/ERC4626BufferPoolMock.sol";
import { PoolMock } from "../../../contracts/test/PoolMock.sol";
import { RouterCommon } from "../../../contracts/RouterCommon.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";
import {ERC4626RateProvider} from "../../../contracts/test/ERC4626RateProvider.sol";

contract BufferInsideVaultWithAaveTest is BaseVaultTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    // Using older block number because convertToAssets function is bricked in the new version of the aToken wrapper
    uint256 constant BLOCK_NUMBER = 17965150;

    address constant aDAI_ADDRESS = 0x098256c06ab24F5655C5506A6488781BD711c14b;
    address constant aUSDC_ADDRESS = 0x57d20c946A7A3812a7225B881CdcD8431D23431C;
    address constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 constant USDC_FACTOR = 1e12;

    // Owner of DAI and USDC in Mainnet
    address constant DONOR_WALLET_ADDRESS = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;

    address payable donor;

    IERC20 internal daiMainnet;
    IERC4626 internal waDAI;
    IERC20 internal usdcMainnet;
    IERC4626 internal waUSDC;

    ERC4626BufferPoolFactoryMock bufferFactory;

    // For two-token pools with waDAI/waUSDC, keep track of sorted token order.
    uint256 internal waDaiIdx;
    uint256 internal waUsdcIdx;

    address internal boostedPool;

    // The boosted pool will have 100x the liquidity of the buffer
    uint256 internal boostedPoolAmount = 1e6 * 1e18;
    uint256 internal bufferAmount = boostedPoolAmount / 100;
    uint256 internal tooLargeSwapAmount = boostedPoolAmount / 2;
    // We will swap with 10% of the buffer
    uint256 internal swapAmount = bufferAmount / 10;

    function setUp() public virtual override {
        vm.createSelectFork({ blockNumber: BLOCK_NUMBER, urlOrAlias: "mainnet" });

        donor = payable(DONOR_WALLET_ADDRESS);
        vm.label(donor, "TokenDonor");

        _setupTokens();

        BaseVaultTest.setUp();

        bufferFactory = new ERC4626BufferPoolFactoryMock(vault, 365 days);

        (waDaiIdx, waUsdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));

        initializeBuffers();
        initializeBoostedPool();
    }

    function initializeBuffers() private {
        _transferTokensFromDonorToUsers();
        _transferTokensFromDonorToBuffers();
    }

    function initializeBoostedPool() private {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[waDaiIdx].token = IERC20(waDAI);
        tokenConfig[waUsdcIdx].token = IERC20(waUSDC);
        tokenConfig[0].tokenType = TokenType.WITH_RATE;
        tokenConfig[1].tokenType = TokenType.WITH_RATE;
        tokenConfig[waDaiIdx].rateProvider = new ERC4626RateProvider(waDAI);
        tokenConfig[waUsdcIdx].rateProvider = new ERC4626RateProvider(waUSDC);

        PoolMock newPool = new PoolMock(IVault(address(vault)), "Boosted Pool", "BOOSTYBOI");

        factoryMock.registerTestPool(address(newPool), tokenConfig, address(0));

        vm.label(address(newPool), "boosted pool");
        boostedPool = address(newPool);

        vm.startPrank(bob);
        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);

        waUSDC.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waUSDC), address(batchRouter), type(uint160).max, type(uint48).max);

        uint256 boostedAmountDai = waDAI.convertToShares(boostedPoolAmount);
        uint256 boostedAmountUSDC = waUSDC.convertToShares(boostedPoolAmount / USDC_FACTOR);

        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[waDaiIdx] = boostedAmountDai;
        tokenAmounts[waUsdcIdx] = boostedAmountUSDC;

        _initPool(boostedPool, tokenAmounts, boostedPoolAmount * 2 - USDC_FACTOR);
        vm.stopPrank();
    }

    function testSwapPreconditions__Fork() public {
        // bob should have the full boostedPool BPT.
        assertGt(IERC20(boostedPool).balanceOf(bob), boostedPoolAmount * 2 - USDC_FACTOR, "Wrong boosted pool BPT amount");

        (IERC20[] memory tokens, , uint256[] memory balancesRaw, , ) = vault.getPoolTokenInfo(boostedPool);
        // The boosted pool should have `boostedPoolAmount` of both tokens.
        assertEq(address(tokens[waDaiIdx]), address(waDAI), "Wrong boosted pool token (waDAI)");
        assertEq(address(tokens[waUsdcIdx]), address(waUSDC), "Wrong boosted pool token (waUSDC)");

        uint256 boostedAmountDai = waDAI.convertToShares(boostedPoolAmount);
        uint256 boostedAmountUSDC = waUSDC.convertToShares(boostedPoolAmount / USDC_FACTOR);

        assertEq(balancesRaw[waDaiIdx], boostedAmountDai, "Wrong boosted pool balance [waDaiIdx]");
        assertEq(balancesRaw[waUsdcIdx], boostedAmountUSDC, "Wrong boosted pool balance [waUsdcIdx]");

        // LP should have correct amount of shares from buffer (total invested amount in base)
        assertApproxEqAbs(
            vault.getBufferShareOfUser(IERC20(waDAI), address(lp)),
            bufferAmount * 2,
            1,
            "Wrong share of waDAI buffer belonging to LP"
        );
        assertApproxEqAbs(
            vault.getBufferShareOfUser(IERC20(waUSDC), address(lp)),
            bufferAmount * 2 / USDC_FACTOR,
            1,
            "Wrong share of waUSDC buffer belonging to LP"
        );

        uint256 baseBalance;
        uint256 wrappedBalance;

        // The vault buffers should each have `bufferAmount` of their respective tokens.
        (baseBalance, wrappedBalance) = vault.getBufferBalance(IERC20(waDAI));
        assertEq(baseBalance, bufferAmount, "Wrong waDAI buffer balance for base token");
        assertEq(wrappedBalance, waDAI.convertToShares(bufferAmount), "Wrong waDAI buffer balance for wrapped token");

        (baseBalance, wrappedBalance) = vault.getBufferBalance(IERC20(waUSDC));
        assertEq(baseBalance, bufferAmount / USDC_FACTOR, "Wrong waUSDC buffer balance for base token");
        assertEq(wrappedBalance, waUSDC.convertToShares(bufferAmount / USDC_FACTOR), "Wrong waUSDC buffer balance for wrapped token");
    }

    function testBoostedPoolSwapWithinBufferRangeExactIn__Fork() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(swapAmount);

        snapStart("forkBoostedPoolSwapExactIn");
        vm.prank(alice);
        (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) = batchRouter
            .swapExactIn(paths, MAX_UINT256, false, bytes(""));
        snapEnd();

        _verifySwapResult(pathAmountsOut, tokensOut, amountsOut, swapAmount, SwapKind.EXACT_IN, swapAmount);
    }
//
//    function testBoostedPoolSwapWithinBufferRangeExactOut__Fork() public {
//        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(swapAmount);
//
//        snapStart("forkBoostedPoolSwapExactOut");
//        vm.prank(alice);
//        (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) = batchRouter
//            .swapExactOut(paths, MAX_UINT256, false, bytes(""));
//        snapEnd();
//
//        _verifySwapResult(pathAmountsIn, tokensIn, amountsIn, swapAmount, SwapKind.EXACT_OUT, swapAmount);
//    }
//
//    function testBoostedPoolSwapOutOfBufferRangeExactIn__Fork() public {
//        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(tooLargeSwapAmount);
//
//        snapStart("forkBoostedPoolSwapTooLarge-ExactIn");
//        vm.prank(alice);
//        (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) = batchRouter
//            .swapExactIn(paths, MAX_UINT256, false, bytes(""));
//        snapEnd();
//
//        _verifySwapResult(pathAmountsOut, tokensOut, amountsOut, tooLargeSwapAmount, SwapKind.EXACT_IN, 0);
//    }
//
//    function testBoostedPoolSwapOutOfBufferRangeExactOut__Fork() public {
//        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(tooLargeSwapAmount);
//
//        snapStart("forkBoostedPoolSwapTooLarge-ExactOut");
//        vm.prank(alice);
//        (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) = batchRouter
//            .swapExactOut(paths, MAX_UINT256, false, bytes(""));
//        snapEnd();
//
//        _verifySwapResult(pathAmountsIn, tokensIn, amountsIn, tooLargeSwapAmount, SwapKind.EXACT_OUT, 0);
//    }
//
    function _buildExactInPaths(
        uint256 amount
    ) private view returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](3);
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);

        // TODO check comment "Transparent" USDC for DAI swap with boosted pool, which holds only wrapped tokens.
        // Since this is exact in, swaps will be executed in the order given.
        // Pre-swap through DAI buffer to get waDAI, then main swap waDAI for waUSDC in the boosted pool,
        // and finally post-swap the waUSDC through the USDC buffer to calculate the USDC amount out.
        // The only token transfers are DAI in (given) and USDC out (calculated).
        steps[0] = IBatchRouter.SwapPathStep({ pool: aDAI_ADDRESS, tokenOut: waDAI, isBuffer: true });
        steps[1] = IBatchRouter.SwapPathStep({ pool: boostedPool, tokenOut: waUSDC, isBuffer: false });
        steps[2] = IBatchRouter.SwapPathStep({ pool: aUSDC_ADDRESS, tokenOut: usdcMainnet, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: daiMainnet,
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

        // TODO check comment "Transparent" USDC for DAI swap with boosted pool, which holds only wrapped tokens.
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

    function _verifySwapResult(
        uint256[] memory paths,
        address[] memory tokens,
        uint256[] memory amounts,
        uint256 expectedDelta,
        SwapKind kind,
        uint256 bufferExpectedDelta
    ) private {
        assertEq(paths.length, 1, "Incorrect output array length");

        assertEq(paths.length, tokens.length, "Output array length mismatch");
        assertEq(tokens.length, amounts.length, "Output array length mismatch");

        // Check results
        assertApproxEqAbs(paths[0], expectedDelta, 1, "Wrong path count");
        assertApproxEqAbs(amounts[0], expectedDelta, 1, "Wrong amounts count");
        assertEq(tokens[0], kind == SwapKind.EXACT_IN ? address(usdc) : address(dai), "Wrong token for SwapKind");

        // Tokens were transferred
        assertApproxEqAbs(dai.balanceOf(alice), defaultBalance - expectedDelta, 1, "Wrong ending balance of DAI");
        assertApproxEqAbs(usdc.balanceOf(alice), defaultBalance + expectedDelta, 1, "Wrong ending balance of USDC");

        uint256[] memory balancesRaw;

        (uint256 daiIdx, uint256 usdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));
        (, , balancesRaw, , ) = vault.getPoolTokenInfo(boostedPool);
        assertEq(balancesRaw[daiIdx], boostedPoolAmount + expectedDelta, "Wrong boosted pool DAI balance");
        assertEq(balancesRaw[usdcIdx], boostedPoolAmount - expectedDelta, "Wrong boosted pool USDC balance");

        uint256 baseBalance;
        uint256 wrappedBalance;
        (baseBalance, wrappedBalance) = vault.getBufferBalance(IERC20(waDAI));
        assertEq(baseBalance, bufferAmount + bufferExpectedDelta, "Wrong DAI buffer pool base balance");
        assertEq(wrappedBalance, bufferAmount - bufferExpectedDelta, "Wrong DAI buffer pool wrapped balance");

        (baseBalance, wrappedBalance) = vault.getBufferBalance(IERC20(waUSDC));
        assertEq(baseBalance, bufferAmount - bufferExpectedDelta, "Wrong USDC buffer pool base balance");
        assertEq(wrappedBalance, bufferAmount + bufferExpectedDelta, "Wrong USDC buffer pool wrapped balance");
    }

    function _setupTokens() private {
        vm.startPrank(lp);
        daiMainnet = IERC20(DAI_ADDRESS);
        waDAI = IERC4626(aDAI_ADDRESS);
        vm.label(DAI_ADDRESS, "DAI");
        vm.label(aDAI_ADDRESS, "aDAI");

        usdcMainnet = IERC20(USDC_ADDRESS);
        waUSDC = IERC4626(aUSDC_ADDRESS);
        vm.label(USDC_ADDRESS, "USDC");
        vm.label(aUSDC_ADDRESS, "aUSDC");
        vm.stopPrank();
    }

    function _transferTokensFromDonorToUsers() private {
        address[] memory usersToTransfer = [address(lp), address(bob), address(alice)].toMemoryArray();

        for (uint256 i = 0; i < usersToTransfer.length; ++i) {
            address userAddress = usersToTransfer[i];

            vm.startPrank(donor);
            daiMainnet.transfer(userAddress, 4 * boostedPoolAmount);
            usdcMainnet.transfer(userAddress, 4 * boostedPoolAmount / USDC_FACTOR);
            vm.stopPrank();

            vm.startPrank(userAddress);
            daiMainnet.approve(address(permit2), MAX_UINT256);
            permit2.approve(address(daiMainnet), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(daiMainnet), address(batchRouter), type(uint160).max, type(uint48).max);
            waDAI.approve(address(permit2), MAX_UINT256);
            permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);

            daiMainnet.approve(address(waDAI), MAX_UINT256);
            waDAI.deposit(boostedPoolAmount, userAddress);

            usdcMainnet.approve(address(permit2), MAX_UINT256);
            permit2.approve(address(usdcMainnet), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(usdcMainnet), address(batchRouter), type(uint160).max, type(uint48).max);
            waUSDC.approve(address(permit2), MAX_UINT256);
            permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(waUSDC), address(batchRouter), type(uint160).max, type(uint48).max);

            usdcMainnet.approve(address(waUSDC), MAX_UINT256);
            waUSDC.deposit(boostedPoolAmount / USDC_FACTOR, userAddress);
            vm.stopPrank();
        }
    }

    function _transferTokensFromDonorToBuffers() private {
        uint256 wrappedBufferAmountDai = waDAI.convertToShares(bufferAmount);
        uint256 wrappedBufferAmountUSDC = waUSDC.convertToShares(bufferAmount / USDC_FACTOR);

        vm.startPrank(lp);
        router.addLiquidityBuffer(waDAI, bufferAmount, wrappedBufferAmountDai, address(lp));
        router.addLiquidityBuffer(waUSDC, bufferAmount / USDC_FACTOR, wrappedBufferAmountUSDC, address(lp));
        vm.stopPrank();
    }
}
