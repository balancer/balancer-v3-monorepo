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

contract BoostedPoolSepoliaTest is BaseVaultTest {
    uint256 private constant BLOCK_NUMBER = 6288761;

    //    IVault internal constant vaultFork = IVault(0x92B5c1CB2999c45804A60d6529D77DeEF00fb839);
    //    IBatchRouter internal constant batchRouter = IBatchRouter(0x90e065b28c9B7464B44f185f5a6b8e4B4c827f2a);
    //    IPermit2 internal constant permit2Fork = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    //    StablePool internal boostedPoolFork = StablePool(0x302B75a27E5e157f93c679dD7A25Fdfcdbc1473c);

    //    address private constant _router = 0xa12Da7dfD0792a10a5b05B575545Bd685798Ce35;

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

    function setUp() public override {
        vm.createSelectFork({ blockNumber: BLOCK_NUMBER, urlOrAlias: "sepolia" });

        BaseVaultTest.setUp();

        _setupTokens();
        _setupLP();
        _setupBuffers();
        _createAndInitializeBoostedPool();
    }

    function testSwapExactIn() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(50e6, 0);

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        (uint256[] memory queryPathAmountsOut, , ) = batchRouter.querySwapExactIn(paths, bytes(""));
        vm.revertTo(snapshotId);

        vm.prank(lp);
        (uint256[] memory actualPathAmountsOut, , ) = batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        assertEq(queryPathAmountsOut[0], actualPathAmountsOut[0], "Query and actual outputs do not match");
    }

    function testSwapExactOut() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(51e6, 50e18);

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        (uint256[] memory queryPathAmountsIn, , ) = batchRouter.querySwapExactOut(paths, bytes(""));
        vm.revertTo(snapshotId);

        vm.prank(lp);
        (uint256[] memory actualPathAmountsIn, , ) = batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        assertEq(queryPathAmountsIn[0], actualPathAmountsIn[0], "Query and actual outputs do not match");
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

        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: usdcFork,
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

        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: usdcFork,
            steps: steps,
            maxAmountIn: maxAmountIn,
            exactAmountOut: exactAmountOut
        });
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
        router.addLiquidityToBuffer(wDAI, 100e18, 100e18, lp);
        router.addLiquidityToBuffer(wUSDC, 100e6, 100e6, lp);
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
