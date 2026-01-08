// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import {
    IUnbalancedAddViaSwapRouter
} from "@balancer-labs/v3-interfaces/contracts/vault/IUnbalancedAddViaSwapRouter.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { UnbalancedAddViaSwapRouter } from "../../contracts/UnbalancedAddViaSwapRouter.sol";
import { PoolFactoryMock } from "../../contracts/test/PoolFactoryMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract UnbalancedAddViaSwapRouterTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    // Needed to avoid stack-too-deep
    struct TestBalances {
        uint256 userWeth;
        uint256 userDai;
        uint256 userBpt;
        uint256 userEth;
        uint256 poolWeth;
        uint256 poolDai;
        uint256 totalSupply;
    }

    string constant POOL_VERSION = "Pool v1";
    uint256 constant DEFAULT_AMP_FACTOR = 200;
    uint256 constant DELTA_RATIO = 1e15; // 0.1% delta
    uint256 constant ETH_DELTA = 1e3;

    string constant version = "Add Unbalanced Liquidity Via Swap Router Test v1";

    UnbalancedAddViaSwapRouter internal unbalancedAddViaSwapRouter;

    // Track the indices for the standard dai/weth pool.
    uint256 internal daiIdx;
    uint256 internal wethIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        unbalancedAddViaSwapRouter = new UnbalancedAddViaSwapRouter(IVault(address(vault)), weth, permit2, version);

        vm.startPrank(alice);
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokens[i].approve(address(permit2), type(uint256).max);
            permit2.approve(
                address(tokens[i]),
                address(unbalancedAddViaSwapRouter),
                type(uint160).max,
                type(uint48).max
            );
        }
        vm.stopPrank();
    }

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "ERC20 Pool";
        string memory symbol = "ERC20POOL";

        (daiIdx, wethIdx) = getSortedIndexes(address(dai), address(weth));

        IERC20[] memory tokens = InputHelpers.sortTokens([address(weth), address(dai)].toMemoryArray().asIERC20());

        newPool = PoolFactoryMock(poolFactory).createPool(name, symbol);
        vm.label(newPool, "ERC20 Pool");

        PoolFactoryMock(poolFactory).registerTestPool(newPool, vault.buildTokenConfig(tokens), poolHooksContract, lp);

        poolArgs = abi.encode(vault, name, symbol);
    }

    /***************************************************************************
                            EXACT_OUT Path Tests
    ***************************************************************************/

    function testExactOutPath__Fuzz(uint256 bptAmount, bool wethIsEth) public {
        TestBalances memory balancesBefore = _getBalances();

        // Request small BPT amount
        bptAmount = bound(bptAmount, balancesBefore.totalSupply / 1000, balancesBefore.totalSupply / 100);

        // Calculate proportional amounts
        uint256 proportionalWeth = (balancesBefore.poolWeth * bptAmount) / balancesBefore.totalSupply;
        uint256 proportionalDai = (balancesBefore.poolDai * bptAmount) / balancesBefore.totalSupply;

        // Request fewer exact tokens than proportional (triggers EXACT_OUT)
        // Proportional gives us too much WETH, so we swap some back
        uint256 exactAmount = (proportionalWeth * 90) / 100; // 10% less
        uint256 maxAdjustableAmount = proportionalDai * 2; // Generous limit since we ADD to adjustable

        IUnbalancedAddViaSwapRouter.AddLiquidityAndSwapParams memory params = IUnbalancedAddViaSwapRouter
            .AddLiquidityAndSwapParams({
                exactBptAmountOut: bptAmount,
                exactToken: weth,
                exactAmount: exactAmount,
                maxAdjustableAmount: maxAdjustableAmount,
                addLiquidityUserData: bytes(""),
                swapUserData: bytes("")
            });

        uint256 snapshot = vm.snapshotState();
        _prankStaticCall();
        uint256[] memory queryAmountsIn = unbalancedAddViaSwapRouter.queryAddLiquidityUnbalanced(pool, alice, params);
        vm.revertToState(snapshot);

        vm.prank(alice);
        uint256[] memory amountsIn = unbalancedAddViaSwapRouter.addLiquidityUnbalanced{
            value: wethIsEth ? exactAmount : 0
        }(pool, MAX_UINT256, wethIsEth, params);

        TestBalances memory balancesAfter = _getBalances();

        // Verify EXACT_OUT path was taken: adjustable token increased from proportional
        assertGt(amountsIn[daiIdx], proportionalDai, "EXACT_OUT: adjustable should increase");

        // Verify exact amount matches
        assertEq(amountsIn[wethIdx], exactAmount, "Exact token amount must match");

        // Verify within limit (technically redundant)
        assertLe(amountsIn[daiIdx], maxAdjustableAmount, "Adjustable within limit");

        // Verify query matches actual
        assertEq(amountsIn, queryAmountsIn, "Query and actual amounts must match");

        // Verify all balances
        _checkBalancesAfterAddLiquidity(balancesBefore, balancesAfter, amountsIn, bptAmount, wethIsEth);
    }

    function testExactOutPathRevertLimitExceeded__Fuzz(uint256 bptAmount) public {
        TestBalances memory balances = _getBalances();

        // Ensure reasonable low BPT amount first
        bptAmount = bound(bptAmount, balances.totalSupply / 1000, balances.totalSupply / 100);

        uint256 proportionalWeth = (balances.poolWeth * bptAmount) / balances.totalSupply;
        uint256 proportionalDai = (balances.poolDai * bptAmount) / balances.totalSupply;

        // Request fewer exact tokens than proportional (triggers EXACT_OUT)
        uint256 exactAmount = (proportionalWeth * 90) / 100;

        // Set limit too low - would need to add more DAI, but limit prevents it
        uint256 maxAdjustableAmount = proportionalDai; // This will be exceeded after the swap

        IUnbalancedAddViaSwapRouter.AddLiquidityAndSwapParams memory params = IUnbalancedAddViaSwapRouter
            .AddLiquidityAndSwapParams({
                exactBptAmountOut: bptAmount,
                exactToken: weth,
                exactAmount: exactAmount,
                maxAdjustableAmount: maxAdjustableAmount,
                addLiquidityUserData: bytes(""),
                swapUserData: bytes("")
            });

        vm.prank(alice);
        vm.expectPartialRevert(IUnbalancedAddViaSwapRouter.AmountInAboveMaxAdjustableAmount.selector);
        unbalancedAddViaSwapRouter.addLiquidityUnbalanced(pool, MAX_UINT256, false, params);
    }

    /***************************************************************************
                            EXACT_IN Path Tests
    ***************************************************************************/

    function testExactInPath__Fuzz(uint256 bptAmount, bool wethIsEth) public {
        TestBalances memory balancesBefore = _getBalances();

        // Request small BPT amount
        bptAmount = bound(bptAmount, balancesBefore.totalSupply / 1000, balancesBefore.totalSupply / 100);

        // Calculate proportional amounts
        uint256 proportionalWeth = (balancesBefore.poolWeth * bptAmount) / balancesBefore.totalSupply;
        uint256 proportionalDai = (balancesBefore.poolDai * bptAmount) / balancesBefore.totalSupply;

        // Request more exact tokens than proportional (triggers EXACT_IN)
        // Proportional gives us too little WETH, so we add more via swap
        uint256 exactAmount = (proportionalWeth * 110) / 100; // 10% more
        uint256 maxAdjustableAmount = proportionalDai * 2; // Generous since we might need more after reduction

        IUnbalancedAddViaSwapRouter.AddLiquidityAndSwapParams memory params = IUnbalancedAddViaSwapRouter
            .AddLiquidityAndSwapParams({
                exactBptAmountOut: bptAmount,
                exactToken: weth,
                exactAmount: exactAmount,
                maxAdjustableAmount: maxAdjustableAmount,
                addLiquidityUserData: bytes(""),
                swapUserData: bytes("")
            });

        uint256 snapshot = vm.snapshotState();
        _prankStaticCall();
        uint256[] memory queryAmountsIn = unbalancedAddViaSwapRouter.queryAddLiquidityUnbalanced(pool, alice, params);
        vm.revertToState(snapshot);

        vm.prank(alice);
        uint256[] memory amountsIn = unbalancedAddViaSwapRouter.addLiquidityUnbalanced{
            value: wethIsEth ? exactAmount : 0
        }(pool, MAX_UINT256, wethIsEth, params);

        TestBalances memory balancesAfter = _getBalances();

        // Verify EXACT_IN path was taken: adjustable token decreased from proportional
        assertLt(amountsIn[daiIdx], proportionalDai, "EXACT_IN: adjustable should decrease");

        // Verify exact amount matches
        assertEq(amountsIn[wethIdx], exactAmount, "Exact token amount must match");

        // Verify within limit (technically redundant)
        assertLe(amountsIn[daiIdx], maxAdjustableAmount, "Adjustable within limit");

        // Verify query matches actual
        assertEq(amountsIn, queryAmountsIn, "Query and actual amounts must match");

        // Verify all balances
        _checkBalancesAfterAddLiquidity(balancesBefore, balancesAfter, amountsIn, bptAmount, wethIsEth);
    }

    function testExactInPathRevertLimitExceeded__Fuzz(uint256 bptAmount) public {
        TestBalances memory balances = _getBalances();

        // Ensure reasonable low BPT amount first
        bptAmount = bound(bptAmount, balances.totalSupply / 1000, balances.totalSupply / 100);

        uint256 proportionalWeth = (balances.poolWeth * bptAmount) / balances.totalSupply;
        uint256 proportionalDai = (balances.poolDai * bptAmount) / balances.totalSupply;

        // Request more exact tokens (triggers EXACT_IN)
        uint256 exactAmount = (proportionalWeth * 110) / 100;

        // Set limit very low - even after EXACT_IN reduces DAI, the final amount will still exceed this
        uint256 maxAdjustableAmount = (proportionalDai * 50) / 100;

        IUnbalancedAddViaSwapRouter.AddLiquidityAndSwapParams memory params = IUnbalancedAddViaSwapRouter
            .AddLiquidityAndSwapParams({
                exactBptAmountOut: bptAmount,
                exactToken: weth,
                exactAmount: exactAmount,
                maxAdjustableAmount: maxAdjustableAmount,
                addLiquidityUserData: bytes(""),
                swapUserData: bytes("")
            });

        vm.prank(alice);
        vm.expectPartialRevert(IUnbalancedAddViaSwapRouter.AmountInAboveMaxAdjustableAmount.selector);
        unbalancedAddViaSwapRouter.addLiquidityUnbalanced(pool, MAX_UINT256, false, params);
    }

    /***************************************************************************
                            Edge Case Tests
    ***************************************************************************/

    function testNonTwoTokenPools() public {
        IERC20[] memory tokens = InputHelpers.sortTokens(
            [address(weth), address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        address threePool = PoolFactoryMock(poolFactory).createPool("Three Tokens", "3TKN");

        PoolFactoryMock(poolFactory).registerTestPool(threePool, vault.buildTokenConfig(tokens), poolHooksContract, lp);

        IUnbalancedAddViaSwapRouter.AddLiquidityAndSwapParams memory params = IUnbalancedAddViaSwapRouter
            .AddLiquidityAndSwapParams({
                exactBptAmountOut: 0,
                exactToken: weth,
                exactAmount: 1e18,
                maxAdjustableAmount: MAX_UINT256,
                addLiquidityUserData: bytes(""),
                swapUserData: bytes("")
            });

        vm.expectRevert(IUnbalancedAddViaSwapRouter.NotTwoTokenPool.selector);
        unbalancedAddViaSwapRouter.addLiquidityUnbalanced(threePool, MAX_UINT256, false, params);
    }

    function testSwapAfterDeadline() public {
        IUnbalancedAddViaSwapRouter.AddLiquidityAndSwapParams memory params = IUnbalancedAddViaSwapRouter
            .AddLiquidityAndSwapParams({
                exactBptAmountOut: 0,
                exactToken: weth,
                exactAmount: 1e18,
                maxAdjustableAmount: MAX_UINT256,
                addLiquidityUserData: bytes(""),
                swapUserData: bytes("")
            });

        vm.expectRevert(ISenderGuard.SwapDeadline.selector);
        unbalancedAddViaSwapRouter.addLiquidityUnbalanced(pool, 0, false, params);
    }

    // Test helpers

    function _getBalances() private view returns (TestBalances memory balances) {
        uint256[] memory poolBalances = vault.getCurrentLiveBalances(pool);
        balances.userWeth = weth.balanceOf(alice);
        balances.userDai = dai.balanceOf(alice);
        balances.userBpt = IERC20(pool).balanceOf(alice);
        balances.userEth = address(alice).balance;
        balances.poolWeth = poolBalances[wethIdx];
        balances.poolDai = poolBalances[daiIdx];
        balances.totalSupply = IERC20(pool).totalSupply();
    }

    function _checkBalancesAfterAddLiquidity(
        TestBalances memory balancesBefore,
        TestBalances memory balancesAfter,
        uint256[] memory amountsIn,
        uint256 bptAmount,
        bool wethIsEth
    ) private view {
        // Check BPT minted
        assertEq(balancesAfter.userBpt, balancesBefore.userBpt + bptAmount, "BPT minted incorrect");

        // Check pool balances increased
        assertEq(balancesAfter.poolWeth, balancesBefore.poolWeth + amountsIn[wethIdx], "Pool WETH balance incorrect");
        assertEq(balancesAfter.poolDai, balancesBefore.poolDai + amountsIn[daiIdx], "Pool DAI balance incorrect");

        // Check user token balances decreased
        if (wethIsEth) {
            assertApproxEqAbs(
                balancesAfter.userEth,
                balancesBefore.userEth - amountsIn[wethIdx],
                ETH_DELTA,
                "Alice ETH balance incorrect"
            );
        } else {
            assertEq(
                balancesAfter.userWeth,
                balancesBefore.userWeth - amountsIn[wethIdx],
                "Alice WETH balance incorrect"
            );
        }
        assertEq(balancesAfter.userDai, balancesBefore.userDai - amountsIn[daiIdx], "Alice DAI balance incorrect");
    }
}
