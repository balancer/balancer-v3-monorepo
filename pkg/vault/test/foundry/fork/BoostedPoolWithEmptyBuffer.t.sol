// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { TokenConfig, TokenType, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";
import { ERC4626RateProvider } from "../../../contracts/test/ERC4626RateProvider.sol";

contract BoostedPoolWithEmptyBufferTest is BaseVaultTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    // Using older block number because convertToAssets function is bricked in the new version of the aToken wrapper.
    uint256 constant BLOCK_NUMBER = 17965150;

    address constant aDAI_ADDRESS = 0x098256c06ab24F5655C5506A6488781BD711c14b;
    address constant aUSDC_ADDRESS = 0x57d20c946A7A3812a7225B881CdcD8431D23431C;
    address constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 constant USDC_FACTOR = 1e12;
    // When converting from DAI to USDC, we get rounding errors on exact outs (1 unit of USDC is 1e12 units of DAI).
    uint256 constant DAI_TO_USDC_FACTOR = USDC_FACTOR * 2;

    // Owner of DAI and USDC in Mainnet
    address constant DONOR_WALLET_ADDRESS = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;

    address payable donor;

    IERC20 internal daiMainnet;
    IERC4626 internal waDAI;
    IERC20 internal usdcMainnet;
    IERC4626 internal waUSDC;

    // For two-token pools with waDAI/waUSDC, keep track of sorted token order.
    uint256 internal waDaiIdx;
    uint256 internal waUsdcIdx;

    address internal boostedPool;

    // The boosted pool will have 100x the liquidity of the buffer.
    uint256 internal boostedPoolAmount = 1e6 * 1e18;
    uint256 internal bufferAmount = boostedPoolAmount / 100;
    uint256 internal tooLargeSwapAmount = boostedPoolAmount / 2;
    // We will swap with 10% of the buffer.
    uint256 internal swapAmount = bufferAmount / 10;

    function setUp() public virtual override {
        vm.createSelectFork({ blockNumber: BLOCK_NUMBER, urlOrAlias: "mainnet" });

        donor = payable(DONOR_WALLET_ADDRESS);
        vm.label(donor, "TokenDonor");

        _setupTokens();

        BaseVaultTest.setUp();

        (waDaiIdx, waUsdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));

        initializeBuffers();
        initializeBoostedPool();
    }

    function initializeBuffers() private {
        _transferTokensFromDonorToUsers();
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

        factoryMock.registerTestPool(address(newPool), tokenConfig, poolHooksContract);

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

    function testSwapPreconditions__Fork() public view {
        // bob should have the full boostedPool BPT.
        assertGt(
            IERC20(boostedPool).balanceOf(bob),
            boostedPoolAmount * 2 - USDC_FACTOR,
            "Wrong boosted pool BPT amount"
        );

        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(boostedPool);
        // The boosted pool should have `boostedPoolAmount` of both tokens.
        assertEq(address(tokens[waDaiIdx]), address(waDAI), "Wrong boosted pool token (waDAI)");
        assertEq(address(tokens[waUsdcIdx]), address(waUSDC), "Wrong boosted pool token (waUSDC)");

        uint256 boostedAmountDai = waDAI.convertToShares(boostedPoolAmount);
        uint256 boostedAmountUSDC = waUSDC.convertToShares(boostedPoolAmount / USDC_FACTOR);

        assertEq(balancesRaw[waDaiIdx], boostedAmountDai, "Wrong boosted pool balance [waDaiIdx]");
        assertEq(balancesRaw[waUsdcIdx], boostedAmountUSDC, "Wrong boosted pool balance [waUsdcIdx]");

        uint256 underlyingBalance;
        uint256 wrappedBalance;

        // The vault buffers should each have 0 tokens.
        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(IERC20(waDAI));
        assertEq(underlyingBalance, 0, "Wrong waDAI buffer balance for underlying token");
        assertEq(wrappedBalance, 0, "Wrong waDAI buffer balance for wrapped token");

        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(IERC20(waUSDC));
        assertEq(underlyingBalance, 0, "Wrong waUSDC buffer balance for underlying token");
        assertEq(wrappedBalance, 0, "Wrong waUSDC buffer balance for wrapped token");
    }

    function testBoostedPoolSwapEmptyBufferExactIn__Fork() public {
        SwapResultLocals memory vars = _createSwapResultLocals(SwapKind.EXACT_IN);
        vars.expectedDeltaDai = swapAmount;
        vars.expectedBufferDeltaDai = 0;
        vars.expectedDeltaUsdc = swapAmount / USDC_FACTOR;
        vars.expectedBufferDeltaUsdc = 0;

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(
            swapAmount,
            swapAmount / USDC_FACTOR - 1
        );

        snapStart("forkBoostedPoolEmptyBufferSwapExactIn");
        vm.prank(alice);
        (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) = batchRouter
            .swapExactIn(paths, MAX_UINT256, false, bytes(""));
        snapEnd();

        _verifySwapResult(pathAmountsOut, tokensOut, amountsOut, vars);
    }

    function testBoostedPoolSwapEmptyBufferExactOut__Fork() public {
        SwapResultLocals memory vars = _createSwapResultLocals(SwapKind.EXACT_OUT);

        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            swapAmount + DAI_TO_USDC_FACTOR,
            swapAmount / USDC_FACTOR
        );

        snapStart("forkBoostedPoolEmptyBufferSwapExactOut");
        vm.prank(alice);
        (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) = batchRouter
            .swapExactOut(paths, MAX_UINT256, false, bytes(""));
        snapEnd();

        // EXACT_IN DAI -> USDC does not introduce rounding issues, since the resulting amountOut is divided by 1e12
        // to get the correct amount of USDC to return.
        //
        // However, EXACT_OUT DAI -> USDC has rounding issues, because amount out is given in 6 digits, and we want an
        // 18 decimals amount in, which is not precisely calculated. The calculation below reproduces what happens in
        // the vault to scale tokens in the swap operation of the boosted pool.
        uint256 expectedWrappedTokenOutUsdc = waUSDC.previewWithdraw(swapAmount / USDC_FACTOR);
        uint256 expectedScaled18WrappedTokenOutUsdc = FixedPoint.mulDown(
            expectedWrappedTokenOutUsdc * USDC_FACTOR,
            waUSDC.convertToAssets(FixedPoint.ONE)
        );
        uint256 expectedScaled18WrappedTokenInDai = FixedPoint.divDown(
            expectedScaled18WrappedTokenOutUsdc,
            waDAI.convertToAssets(FixedPoint.ONE)
        );

        vars.expectedDeltaDai = waDAI.convertToAssets(expectedScaled18WrappedTokenInDai);
        vars.expectedBufferDeltaDai = 0;
        vars.expectedDeltaUsdc = swapAmount / USDC_FACTOR;
        vars.expectedBufferDeltaUsdc = 0;

        _verifySwapResult(pathAmountsIn, tokensIn, amountsIn, vars);
    }

    function _buildExactInPaths(
        uint256 exactAmountIn,
        uint256 minAmountOut
    ) private view returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](3);
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);

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
            exactAmountIn: exactAmountIn,
            minAmountOut: minAmountOut // rebalance tests are a wei off
        });
    }

    function _buildExactOutPaths(
        uint256 maxAmountIn,
        uint256 exactAmountOut
    ) private view returns (IBatchRouter.SwapPathExactAmountOut[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](3);
        paths = new IBatchRouter.SwapPathExactAmountOut[](1);

        // Since this is exact out, swaps will be executed in reverse order (though we submit in logical order).
        // Pre-swap through the USDC buffer to get waUSDC, then main swap waUSDC for waDAI in the boosted pool,
        // and finally post-swap the waDAI for DAI through the DAI buffer to calculate the DAI amount in.
        // The only token transfers are DAI in (calculated) and USDC out (given).
        steps[0] = IBatchRouter.SwapPathStep({ pool: aDAI_ADDRESS, tokenOut: waDAI, isBuffer: true });
        steps[1] = IBatchRouter.SwapPathStep({ pool: boostedPool, tokenOut: waUSDC, isBuffer: false });
        steps[2] = IBatchRouter.SwapPathStep({ pool: aUSDC_ADDRESS, tokenOut: usdcMainnet, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: daiMainnet,
            steps: steps,
            maxAmountIn: maxAmountIn,
            exactAmountOut: exactAmountOut
        });
    }

    struct SwapResultLocals {
        SwapKind kind;
        uint256 aliceBalanceBeforeSwapDai;
        uint256 aliceBalanceBeforeSwapUsdc;
        uint256 bufferBalanceBeforeSwapDai;
        uint256 bufferBalanceBeforeSwapWaDai;
        uint256 bufferBalanceBeforeSwapUsdc;
        uint256 bufferBalanceBeforeSwapWaUsdc;
        uint256 boostedPoolBalanceBeforeSwapWaDai;
        uint256 boostedPoolBalanceBeforeSwapWaUsdc;
        uint256 expectedDeltaDai;
        uint256 expectedDeltaUsdc;
        uint256 expectedBufferDeltaDai;
        uint256 expectedBufferDeltaUsdc;
    }

    function _createSwapResultLocals(SwapKind kind) private view returns (SwapResultLocals memory vars) {
        vars.kind = kind;
        vars.aliceBalanceBeforeSwapDai = daiMainnet.balanceOf(alice);
        vars.aliceBalanceBeforeSwapUsdc = usdcMainnet.balanceOf(alice);

        uint256 underlyingBalance;
        uint256 wrappedBalance;
        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(IERC20(waDAI));
        vars.bufferBalanceBeforeSwapDai = underlyingBalance;
        vars.bufferBalanceBeforeSwapWaDai = wrappedBalance;
        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(IERC20(waUSDC));
        vars.bufferBalanceBeforeSwapUsdc = underlyingBalance;
        vars.bufferBalanceBeforeSwapWaUsdc = wrappedBalance;

        uint256[] memory balancesRaw;
        (uint256 daiIdx, uint256 usdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));
        (, , balancesRaw, ) = vault.getPoolTokenInfo(boostedPool);
        vars.boostedPoolBalanceBeforeSwapWaDai = balancesRaw[daiIdx];
        vars.boostedPoolBalanceBeforeSwapWaUsdc = balancesRaw[usdcIdx];
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
            assertLe(paths[0], vars.expectedDeltaUsdc, "paths AmountOut must be <= expected amountOut");
            assertApproxEqAbs(paths[0], vars.expectedDeltaUsdc, 1, "Wrong path count");
            assertLe(paths[0], vars.expectedDeltaUsdc, "amounts AmountOut must be <= expected amountOut");
            assertApproxEqAbs(amounts[0], vars.expectedDeltaUsdc, 1, "Wrong amounts count");
            assertEq(tokens[0], USDC_ADDRESS, "Wrong token for SwapKind");
        } else {
            // Rounding issues occurs in favor of vault, and are very small
            assertGe(paths[0], vars.expectedDeltaDai, "paths AmountIn must be >= expected amountIn");
            assertApproxEqAbs(paths[0], vars.expectedDeltaDai, 5, "Wrong path count");
            assertGe(amounts[0], vars.expectedDeltaDai, "amounts AmountIn must be >= expected amountIn");
            assertApproxEqAbs(amounts[0], vars.expectedDeltaDai, 5, "Wrong amounts count");
            assertEq(tokens[0], DAI_ADDRESS, "Wrong token for SwapKind");
        }

        // Tokens were transferred
        assertLe(
            daiMainnet.balanceOf(alice),
            vars.aliceBalanceBeforeSwapDai - vars.expectedDeltaDai,
            "Alice balance DAI must be <= expected balance"
        );
        assertApproxEqAbs(
            daiMainnet.balanceOf(alice),
            vars.aliceBalanceBeforeSwapDai - vars.expectedDeltaDai,
            5,
            "Wrong ending balance of DAI for Alice"
        );
        assertLe(
            usdcMainnet.balanceOf(alice),
            vars.aliceBalanceBeforeSwapUsdc + vars.expectedDeltaUsdc,
            "Alice balance USDC must be <= expected balance"
        );
        assertApproxEqAbs(
            usdcMainnet.balanceOf(alice),
            vars.aliceBalanceBeforeSwapUsdc + vars.expectedDeltaUsdc,
            1,
            "Wrong ending balance of USDC for Alice"
        );

        uint256[] memory balancesRaw;

        (uint256 daiIdx, uint256 usdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));
        (, , balancesRaw, ) = vault.getPoolTokenInfo(boostedPool);
        assertApproxEqAbs(
            balancesRaw[daiIdx],
            vars.boostedPoolBalanceBeforeSwapWaDai + waDAI.convertToShares(vars.expectedDeltaDai),
            5,
            "Wrong boosted pool DAI balance"
        );
        assertApproxEqAbs(
            balancesRaw[usdcIdx],
            vars.boostedPoolBalanceBeforeSwapWaUsdc - waUSDC.convertToShares(vars.expectedDeltaUsdc),
            1,
            "Wrong boosted pool USDC balance"
        );

        uint256 underlyingBalance;
        uint256 wrappedBalance;
        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(IERC20(waDAI));
        assertEq(underlyingBalance, 0, "Wrong DAI buffer pool underlying balance");
        assertEq(wrappedBalance, 0, "Wrong DAI buffer pool wrapped balance");

        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(IERC20(waUSDC));
        assertEq(underlyingBalance, 0, "Wrong USDC buffer pool underlying balance");
        assertEq(wrappedBalance, 0, "Wrong USDC buffer pool wrapped balance");
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
        address[] memory usersToTransfer = [lp, bob, alice].toMemoryArray();

        for (uint256 i = 0; i < usersToTransfer.length; ++i) {
            address userAddress = usersToTransfer[i];

            vm.startPrank(donor);
            daiMainnet.transfer(userAddress, 4 * boostedPoolAmount);
            usdcMainnet.transfer(userAddress, (4 * boostedPoolAmount) / USDC_FACTOR);
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
}
