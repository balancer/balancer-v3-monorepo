// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { ICompositeLiquidityRouter } from "@balancer-labs/v3-interfaces/contracts/vault/ICompositeLiquidityRouter.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BalancerPoolToken } from "../../contracts/BalancerPoolToken.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract CompositeLiquidityRouterNestedPoolsTest is BaseVaultTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    address internal parentPool;
    address internal childPoolA;
    address internal childPoolB;

    // Max of 5 wei of error when retrieving tokens from a nested pool.
    uint256 internal constant MAX_ROUND_ERROR = 5;

    function setUp() public override {
        BaseVaultTest.setUp();

        childPoolA = _createPool([address(usdc), address(weth)].toMemoryArray(), "childPoolA");
        childPoolB = _createPool([address(wsteth), address(dai)].toMemoryArray(), "childPoolB");
        parentPool = _createPool(
            [address(childPoolA), address(childPoolB), address(dai)].toMemoryArray(),
            "parentPool"
        );

        vm.startPrank(lp);
        uint256 childPoolABptOut = _initPool(childPoolA, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        uint256 childPoolBBptOut = _initPool(childPoolB, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);

        uint256[] memory tokenIndexes = getSortedIndexes([childPoolA, childPoolB, address(dai)].toMemoryArray());
        uint256 poolAIdx = tokenIndexes[0];
        uint256 poolBIdx = tokenIndexes[1];
        uint256 daiIdx = tokenIndexes[2];

        uint256[] memory amountsInParentPool = new uint256[](3);
        amountsInParentPool[daiIdx] = poolInitAmount;
        amountsInParentPool[poolAIdx] = childPoolABptOut;
        amountsInParentPool[poolBIdx] = childPoolBBptOut;
        vm.stopPrank();

        approveForPool(IERC20(childPoolA));
        approveForPool(IERC20(childPoolB));
        approveForPool(IERC20(parentPool));

        vm.startPrank(lp);
        _initPool(parentPool, amountsInParentPool, 0);
        vm.stopPrank();
    }

    /*******************************************************************************
                                Add liquidity
    *******************************************************************************/

    function testAddLiquidityNestedPool() public {
        uint256 daiAmount = poolInitAmount;
        uint256 usdcAmount = poolInitAmount;
        uint256 wethAmount = poolInitAmount;
        uint256 wstEthAmount = poolInitAmount;

        uint256 minBptOut = poolInitAmount;

        NestedPoolTestLocals memory vars = _createNestedPoolTestLocals();

        address[] memory tokensIn = new address[](4);
        tokensIn[vars.daiIdx] = address(dai);
        tokensIn[vars.usdcIdx] = address(usdc);
        tokensIn[vars.wethIdx] = address(weth);
        tokensIn[vars.wstethIdx] = address(wsteth);

        uint256[] memory amountsIn = new uint256[](4);
        amountsIn[vars.daiIdx] = daiAmount;
        amountsIn[vars.usdcIdx] = usdcAmount;
        amountsIn[vars.wethIdx] = wethAmount;
        amountsIn[vars.wstethIdx] = wstEthAmount;

        vm.prank(lp);
        uint256 exactBptOut = compositeLiquidityRouter.addLiquidityUnbalancedNestedPool(
            parentPool,
            tokensIn,
            amountsIn,
            minBptOut,
            bytes("")
        );

        _fillNestedPoolTestLocalsAfter(vars);
        uint256 mintedChildPoolABpts = vars.childPoolAAfter.totalSupply - vars.childPoolABefore.totalSupply;
        uint256 mintedChildPoolBBpts = vars.childPoolBAfter.totalSupply - vars.childPoolBBefore.totalSupply;

        // Check LP Balances.
        assertEq(vars.lpAfter.dai, vars.lpBefore.dai - amountsIn[vars.daiIdx], "LP Dai Balance is wrong");
        assertEq(vars.lpAfter.weth, vars.lpBefore.weth - amountsIn[vars.wethIdx], "LP Weth Balance is wrong");
        assertEq(vars.lpAfter.wsteth, vars.lpBefore.wsteth - amountsIn[vars.wstethIdx], "LP Wsteth Balance is wrong");
        assertEq(vars.lpAfter.usdc, vars.lpBefore.usdc - amountsIn[vars.usdcIdx], "LP Usdc Balance is wrong");
        assertEq(vars.lpAfter.childPoolABpt, vars.lpBefore.childPoolABpt, "LP ChildPoolA BPT Balance is wrong");
        assertEq(vars.lpAfter.childPoolBBpt, vars.lpBefore.childPoolBBpt, "LP ChildPoolB BPT Balance is wrong");
        assertEq(
            vars.lpAfter.parentPoolBpt,
            vars.lpBefore.parentPoolBpt + exactBptOut,
            "LP ParentPool BPT Balance is wrong"
        );

        // Check Vault Balances.
        assertEq(vars.vaultAfter.dai, vars.vaultBefore.dai + amountsIn[vars.daiIdx], "Vault Dai Balance is wrong");
        assertEq(vars.vaultAfter.weth, vars.vaultBefore.weth + amountsIn[vars.wethIdx], "Vault Weth Balance is wrong");
        assertEq(
            vars.vaultAfter.wsteth,
            vars.vaultBefore.wsteth + amountsIn[vars.wstethIdx],
            "Vault Wsteth Balance is wrong"
        );
        assertEq(vars.vaultAfter.usdc, vars.vaultBefore.usdc + amountsIn[vars.usdcIdx], "Vault Usdc Balance is wrong");
        // Since all Child Pool BPTs were allocated in the parent pool, vault is holding all of the minted BPTs.
        assertEq(
            vars.vaultAfter.childPoolABpt,
            vars.vaultBefore.childPoolABpt + mintedChildPoolABpts,
            "Vault ChildPoolA BPT Balance is wrong"
        );
        assertEq(
            vars.vaultAfter.childPoolBBpt,
            vars.vaultBefore.childPoolBBpt + mintedChildPoolBBpts,
            "Vault ChildPoolB BPT Balance is wrong"
        );
        // Vault's parent pool BPTs did not change.
        assertEq(
            vars.vaultAfter.parentPoolBpt,
            vars.vaultBefore.parentPoolBpt,
            "Vault ParentPool BPT Balance is wrong"
        );

        // Check ChildPoolA balances.
        assertEq(
            vars.childPoolAAfter.weth,
            vars.childPoolABefore.weth + amountsIn[vars.wethIdx],
            "ChildPoolA Weth Balance is wrong"
        );
        assertEq(
            vars.childPoolAAfter.usdc,
            vars.childPoolABefore.usdc + amountsIn[vars.usdcIdx],
            "ChildPoolA Usdc Balance is wrong"
        );

        // Check ChildPoolB balances.
        assertApproxEqAbs(
            vars.childPoolBAfter.dai,
            vars.childPoolBBefore.dai + amountsIn[vars.daiIdx],
            MAX_ROUND_ERROR,
            "ChildPoolB Dai Balance is wrong"
        );
        assertEq(
            vars.childPoolBAfter.wsteth,
            vars.childPoolBBefore.wsteth + amountsIn[vars.wstethIdx],
            "ChildPoolB Wsteth Balance is wrong"
        );

        // Check ParentPool balances.
        // The ParentPool's DAI balance does not change since all DAI amount is inserted in the child pool A.
        assertEq(vars.parentPoolAfter.dai, vars.parentPoolBefore.dai, "ParentPool Dai Balance is wrong");
        assertEq(
            vars.parentPoolAfter.childPoolABpt,
            vars.parentPoolBefore.childPoolABpt + mintedChildPoolABpts,
            "ParentPool ChildPoolA BPT Balance is wrong"
        );
        assertEq(
            vars.parentPoolAfter.childPoolBBpt,
            vars.parentPoolBefore.childPoolBBpt + mintedChildPoolBBpts,
            "ParentPool ChildPoolB BPT Balance is wrong"
        );
    }

    /*******************************************************************************
                              Remove liquidity
    *******************************************************************************/

    function testRemoveLiquidityNestedPool__Fuzz(uint256 proportionToRemove) public {
        // Remove between 0.0001% and 50% of each pool liquidity.
        proportionToRemove = bound(proportionToRemove, 1e12, 50e16);

        uint256 totalPoolBPTs = BalancerPoolToken(parentPool).totalSupply();
        // Since LP is the owner of all BPT supply, and part of the BPTs were burned in the initialization step, using
        // totalSupply is more accurate to remove exactly the proportion that we intend from each pool.
        uint256 exactBptIn = totalPoolBPTs.mulDown(proportionToRemove);

        NestedPoolTestLocals memory vars = _createNestedPoolTestLocals();

        // During pool initialization, POOL_MINIMUM_TOTAL_SUPPLY amount of BPT is burned to address(0), so that the
        // pool cannot be completely drained. We need to discount this amount of tokens from the total liquidity that
        // we can extract from the child pools.
        uint256 deadTokens = (POOL_MINIMUM_TOTAL_SUPPLY / 2).mulDown(proportionToRemove);

        address[] memory tokensOut = new address[](4);
        tokensOut[vars.daiIdx] = address(dai);
        tokensOut[vars.wethIdx] = address(weth);
        tokensOut[vars.wstethIdx] = address(wsteth);
        tokensOut[vars.usdcIdx] = address(usdc);

        uint256[] memory expectedAmountsOut = new uint256[](4);
        // DAI exists in childPoolB and parentPool, so we expect 2x more DAI than the other tokens.
        // Since pools are in their initial state, we can use poolInitAmount as the balance of each token in the pool.
        // Also, we only need to account for deadTokens once, since we calculate the BPT in for the parent pool using
        // totalSupply (so the burned POOL_MINIMUM_TOTAL_SUPPLY amount does not affect the BPT in circulation, and the
        // amounts out are perfectly proportional to the parent pool balance).
        expectedAmountsOut[vars.daiIdx] =
            (poolInitAmount.mulDown(proportionToRemove) * 2) -
            deadTokens -
            MAX_ROUND_ERROR;
        expectedAmountsOut[vars.wethIdx] = poolInitAmount.mulDown(proportionToRemove) - deadTokens - MAX_ROUND_ERROR;
        expectedAmountsOut[vars.wstethIdx] = poolInitAmount.mulDown(proportionToRemove) - deadTokens - MAX_ROUND_ERROR;
        expectedAmountsOut[vars.usdcIdx] = poolInitAmount.mulDown(proportionToRemove) - deadTokens - MAX_ROUND_ERROR;

        vm.prank(lp);
        uint256[] memory amountsOut = compositeLiquidityRouter.removeLiquidityProportionalNestedPool(
            parentPool,
            exactBptIn,
            tokensOut,
            expectedAmountsOut,
            bytes("")
        );

        _fillNestedPoolTestLocalsAfter(vars);
        uint256 burnedChildPoolABpts = vars.childPoolABefore.totalSupply - vars.childPoolAAfter.totalSupply;
        uint256 burnedChildPoolBBpts = vars.childPoolBBefore.totalSupply - vars.childPoolBAfter.totalSupply;

        // Check returned token amounts.
        assertEq(amountsOut.length, 4, "amountsOut length is wrong");
        assertApproxEqAbs(
            expectedAmountsOut[vars.daiIdx],
            amountsOut[vars.daiIdx],
            MAX_ROUND_ERROR,
            "DAI amount out is wrong"
        );
        assertApproxEqAbs(
            expectedAmountsOut[vars.wethIdx],
            amountsOut[vars.wethIdx],
            MAX_ROUND_ERROR,
            "WETH amount out is wrong"
        );
        assertApproxEqAbs(
            expectedAmountsOut[vars.wstethIdx],
            amountsOut[vars.wstethIdx],
            MAX_ROUND_ERROR,
            "WstETH amount out is wrong"
        );
        assertApproxEqAbs(
            expectedAmountsOut[vars.usdcIdx],
            amountsOut[vars.usdcIdx],
            MAX_ROUND_ERROR,
            "USDC amount out is wrong"
        );

        // Check LP Balances.
        assertEq(vars.lpAfter.dai, vars.lpBefore.dai + amountsOut[vars.daiIdx], "LP Dai Balance is wrong");
        assertEq(vars.lpAfter.weth, vars.lpBefore.weth + amountsOut[vars.wethIdx], "LP Weth Balance is wrong");
        assertEq(vars.lpAfter.wsteth, vars.lpBefore.wsteth + amountsOut[vars.wstethIdx], "LP Wsteth Balance is wrong");
        assertEq(vars.lpAfter.usdc, vars.lpBefore.usdc + amountsOut[vars.usdcIdx], "LP Usdc Balance is wrong");
        assertEq(vars.lpAfter.childPoolABpt, vars.lpBefore.childPoolABpt, "LP ChildPoolA BPT Balance is wrong");
        assertEq(vars.lpAfter.childPoolBBpt, vars.lpBefore.childPoolBBpt, "LP ChildPoolB BPT Balance is wrong");
        assertEq(
            vars.lpAfter.parentPoolBpt,
            vars.lpBefore.parentPoolBpt - exactBptIn,
            "LP ParentPool BPT Balance is wrong"
        );

        // Check Vault Balances.
        assertEq(vars.vaultAfter.dai, vars.vaultBefore.dai - amountsOut[vars.daiIdx], "Vault Dai Balance is wrong");
        assertEq(vars.vaultAfter.weth, vars.vaultBefore.weth - amountsOut[vars.wethIdx], "Vault Weth Balance is wrong");
        assertEq(
            vars.vaultAfter.wsteth,
            vars.vaultBefore.wsteth - amountsOut[vars.wstethIdx],
            "Vault Wsteth Balance is wrong"
        );
        assertEq(vars.vaultAfter.usdc, vars.vaultBefore.usdc - amountsOut[vars.usdcIdx], "Vault Usdc Balance is wrong");
        // Since all Child Pool BPTs were allocated in the parent pool, vault was holding all of them. Since part of
        // them was burned when liquidity was removed, we need to discount this amount from the vault reserves.
        assertEq(
            vars.vaultAfter.childPoolABpt,
            vars.vaultBefore.childPoolABpt - burnedChildPoolABpts,
            "Vault ChildPoolA BPT Balance is wrong"
        );
        assertEq(
            vars.vaultAfter.childPoolBBpt,
            vars.vaultBefore.childPoolBBpt - burnedChildPoolBBpts,
            "Vault ChildPoolB BPT Balance is wrong"
        );
        // Vault did not hold the parent pool BPTs.
        assertEq(
            vars.vaultAfter.parentPoolBpt,
            vars.vaultBefore.parentPoolBpt,
            "Vault ParentPool BPT Balance is wrong"
        );

        // Check ChildPoolA
        assertEq(
            vars.childPoolAAfter.weth,
            vars.childPoolABefore.weth - amountsOut[vars.wethIdx],
            "ChildPoolA Weth Balance is wrong"
        );
        assertEq(
            vars.childPoolAAfter.usdc,
            vars.childPoolABefore.usdc - amountsOut[vars.usdcIdx],
            "ChildPoolA Usdc Balance is wrong"
        );

        // Check ChildPoolB
        // Since DAI amountOut comes from parentPool and childPoolB, we need to calculate the proportion that comes
        // from childPoolB.
        assertApproxEqAbs(
            vars.childPoolBAfter.dai,
            vars.childPoolBBefore.dai - (amountsOut[vars.daiIdx] - poolInitAmount.mulDown(proportionToRemove)),
            MAX_ROUND_ERROR,
            "ChildPoolB Dai Balance is wrong"
        );
        assertEq(
            vars.childPoolBAfter.wsteth,
            vars.childPoolBBefore.wsteth - amountsOut[vars.wstethIdx],
            "ChildPoolB Wsteth Balance is wrong"
        );

        // Check ParentPool
        assertApproxEqAbs(
            vars.parentPoolAfter.dai,
            vars.parentPoolBefore.dai -
                (amountsOut[vars.daiIdx] -
                    (poolInitAmount - (POOL_MINIMUM_TOTAL_SUPPLY / 2)).mulDown(proportionToRemove)),
            MAX_ROUND_ERROR,
            "ParentPool Dai Balance is wrong"
        );
        assertEq(
            vars.parentPoolAfter.childPoolABpt,
            vars.parentPoolBefore.childPoolABpt - burnedChildPoolABpts,
            "ParentPool ChildPoolA BPT Balance is wrong"
        );
        assertEq(
            vars.parentPoolAfter.childPoolBBpt,
            vars.parentPoolBefore.childPoolBBpt - burnedChildPoolBBpts,
            "ParentPool ChildPoolB BPT Balance is wrong"
        );
    }

    function testRemoveLiquidityNestedPoolLimits() public {
        // Remove 10% of pool liquidity.
        uint256 proportionToRemove = 10e16;

        uint256 totalPoolBPTs = BalancerPoolToken(parentPool).totalSupply();
        // Since LP is the owner of all BPT supply, and part of the BPTs were burned in the initialization step, using
        // totalSupply is more accurate to remove exactly the proportion that we intend from each pool.
        uint256 exactBptIn = totalPoolBPTs.mulDown(proportionToRemove);

        NestedPoolTestLocals memory vars = _createNestedPoolTestLocals();

        // During pool initialization, POOL_MINIMUM_TOTAL_SUPPLY amount of BPT is burned to address(0), so that the
        // pool cannot be completely drained. We need to discount this amount of tokens from the total liquidity that
        // we can extract from the child pools.
        uint256 deadTokens = (POOL_MINIMUM_TOTAL_SUPPLY / 2).mulDown(proportionToRemove);

        address[] memory tokensOut = new address[](4);
        tokensOut[vars.daiIdx] = address(dai);
        tokensOut[vars.wethIdx] = address(weth);
        tokensOut[vars.wstethIdx] = address(wsteth);
        tokensOut[vars.usdcIdx] = address(usdc);

        uint256[] memory minAmountsOut = new uint256[](4);
        // Expect minAmountsOut to be the liquidity of the pool, which is more than what we should return,
        // causing it to revert.
        minAmountsOut[vars.daiIdx] = poolInitAmount;
        minAmountsOut[vars.wethIdx] = poolInitAmount;
        minAmountsOut[vars.wstethIdx] = poolInitAmount;
        minAmountsOut[vars.usdcIdx] = poolInitAmount;

        // DAI exists in childPoolB and parentPool, so we expect 2x more DAI than the other tokens.
        // Since pools are in their initial state, we can use poolInitAmount as the balance of each token in the pool.
        // Also, we only need to account for deadTokens once, since we calculate the BPT in for the parent pool using
        // totalSupply (so the burned POOL_MINIMUM_TOTAL_SUPPLY amount does not affect the BPT in circulation, and the
        // amounts out are perfectly proportional to the parent pool balance).

        uint256 daiExpectedAmountOut = (poolInitAmount.mulDown(proportionToRemove) * 2) - deadTokens;

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.AmountOutBelowMin.selector,
                address(dai),
                daiExpectedAmountOut,
                poolInitAmount
            )
        );
        vm.prank(lp);
        compositeLiquidityRouter.removeLiquidityProportionalNestedPool(
            parentPool,
            exactBptIn,
            tokensOut,
            minAmountsOut,
            bytes("")
        );
    }

    function testRemoveLiquidityNestedPoolWrongMinAmountsOut() public {
        // Remove 10% of pool liquidity.
        uint256 proportionToRemove = 10e16;

        uint256 totalPoolBPTs = BalancerPoolToken(parentPool).totalSupply();
        // Since LP is the owner of all BPT supply, and part of the BPTs were burned in the initialization step, using
        // totalSupply is more accurate to remove exactly the proportion that we intend from each pool.
        uint256 exactBptIn = totalPoolBPTs.mulDown(proportionToRemove);

        NestedPoolTestLocals memory vars = _createNestedPoolTestLocals();

        address[] memory tokensOut = new address[](4);
        tokensOut[vars.daiIdx] = address(dai);
        tokensOut[vars.wethIdx] = address(weth);
        tokensOut[vars.wstethIdx] = address(wsteth);
        tokensOut[vars.usdcIdx] = address(usdc);

        // Notice that minAmountsOut have a different length than tokensOut, so the transaction should revert.
        uint256[] memory minAmountsOut = new uint256[](3);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        minAmountsOut[2] = 1;

        vm.expectRevert(abi.encodeWithSelector(ICompositeLiquidityRouter.WrongMinAmountsOutLength.selector));

        vm.prank(lp);
        compositeLiquidityRouter.removeLiquidityProportionalNestedPool(
            parentPool,
            exactBptIn,
            tokensOut,
            minAmountsOut,
            bytes("")
        );
    }

    function testRemoveLiquidityNestedPoolWrongTokenArray() public {
        // Remove 10% of pool liquidity.
        uint256 proportionToRemove = 10e16;

        uint256 totalPoolBPTs = BalancerPoolToken(parentPool).totalSupply();
        // Since LP is the owner of all BPT supply, and part of the BPTs were burned in the initialization step, using
        // totalSupply is more accurate to remove exactly the proportion that we intend from each pool.
        uint256 exactBptIn = totalPoolBPTs.mulDown(proportionToRemove);

        // DAI should be in the tokensOut array, but is not, so the transaction should revert.
        // Order extracted from _currentSwapTokensOut().values() of `removeLiquidityProportionalNestedPool` after
        // all child pools were called.
        address[] memory expectedTokensOut = new address[](4);
        expectedTokensOut[0] = address(dai);
        expectedTokensOut[1] = address(weth);
        expectedTokensOut[2] = address(usdc);
        expectedTokensOut[3] = address(wsteth);

        // Notice that tokensOut and minAmountsOut do not have DAI, so the transaction will revert.
        address[] memory tokensOut = new address[](3);
        tokensOut[0] = address(weth);
        tokensOut[1] = address(wsteth);
        tokensOut[2] = address(usdc);

        uint256[] memory minAmountsOut = new uint256[](3);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        minAmountsOut[2] = 1;

        vm.expectRevert(
            abi.encodeWithSelector(ICompositeLiquidityRouter.WrongTokensOut.selector, expectedTokensOut, tokensOut)
        );

        vm.prank(lp);
        compositeLiquidityRouter.removeLiquidityProportionalNestedPool(
            parentPool,
            exactBptIn,
            tokensOut,
            minAmountsOut,
            bytes("")
        );
    }

    function testRemoveLiquidityNestedPoolRepeatedTokens() public {
        // Remove 10% of pool liquidity.
        uint256 proportionToRemove = 10e16;

        uint256 totalPoolBPTs = BalancerPoolToken(parentPool).totalSupply();
        // Since LP is the owner of all BPT supply, and part of the BPTs were burned in the initialization step, using
        // totalSupply is more accurate to remove exactly the proportion that we intend from each pool.
        uint256 exactBptIn = totalPoolBPTs.mulDown(proportionToRemove);

        // DAI should be in the tokensOut array, but is not, so the transaction should revert.
        // Order extracted from _currentSwapTokensOut().values() of `removeLiquidityProportionalNestedPool` after
        // all child pools were called.
        address[] memory expectedTokensOut = new address[](4);
        expectedTokensOut[0] = address(dai);
        expectedTokensOut[1] = address(weth);
        expectedTokensOut[2] = address(usdc);
        expectedTokensOut[3] = address(wsteth);

        // Notice that tokensOut has a repeated token, so the transaction should be reverted.
        address[] memory tokensOut = new address[](4);
        tokensOut[0] = address(dai);
        tokensOut[1] = address(weth);
        tokensOut[2] = address(dai);
        tokensOut[3] = address(usdc);

        uint256[] memory minAmountsOut = new uint256[](4);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        minAmountsOut[2] = 1;
        minAmountsOut[3] = 1;

        vm.expectRevert(
            abi.encodeWithSelector(ICompositeLiquidityRouter.WrongTokensOut.selector, expectedTokensOut, tokensOut)
        );

        vm.prank(lp);
        compositeLiquidityRouter.removeLiquidityProportionalNestedPool(
            parentPool,
            exactBptIn,
            tokensOut,
            minAmountsOut,
            bytes("")
        );
    }

    struct NestedPoolTestLocals {
        uint256 daiIdx;
        uint256 wethIdx;
        uint256 wstethIdx;
        uint256 usdcIdx;
        TokenBalances lpBefore;
        TokenBalances lpAfter;
        TokenBalances vaultBefore;
        TokenBalances vaultAfter;
        TokenBalances childPoolABefore;
        TokenBalances childPoolAAfter;
        TokenBalances childPoolBBefore;
        TokenBalances childPoolBAfter;
        TokenBalances parentPoolBefore;
        TokenBalances parentPoolAfter;
    }

    struct TokenBalances {
        uint256 dai;
        uint256 weth;
        uint256 wsteth;
        uint256 usdc;
        uint256 childPoolABpt;
        uint256 childPoolBBpt;
        uint256 parentPoolBpt;
        uint256 totalSupply;
    }

    function _createNestedPoolTestLocals() private view returns (NestedPoolTestLocals memory vars) {
        // Create output token indexes, randomly chosen (no sort logic).
        (vars.daiIdx, vars.wethIdx, vars.wstethIdx, vars.usdcIdx) = (0, 1, 2, 3);

        vars.lpBefore = _getBalances(lp);
        vars.vaultBefore = _getBalances(address(vault));
        vars.childPoolABefore = _getPoolBalances(childPoolA);
        vars.childPoolBBefore = _getPoolBalances(childPoolB);
        vars.parentPoolBefore = _getPoolBalances(parentPool);
    }

    function _fillNestedPoolTestLocalsAfter(NestedPoolTestLocals memory vars) private view {
        vars.lpAfter = _getBalances(lp);
        vars.vaultAfter = _getBalances(address(vault));
        vars.childPoolAAfter = _getPoolBalances(childPoolA);
        vars.childPoolBAfter = _getPoolBalances(childPoolB);
        vars.parentPoolAfter = _getPoolBalances(parentPool);
    }

    function _getBalances(address entity) private view returns (TokenBalances memory balances) {
        balances.dai = dai.balanceOf(entity);
        balances.weth = weth.balanceOf(entity);
        balances.wsteth = wsteth.balanceOf(entity);
        balances.usdc = usdc.balanceOf(entity);
        balances.childPoolABpt = IERC20(childPoolA).balanceOf(entity);
        balances.childPoolBBpt = IERC20(childPoolB).balanceOf(entity);
        balances.parentPoolBpt = IERC20(parentPool).balanceOf(entity);
    }

    function _getPoolBalances(address pool) private view returns (TokenBalances memory balances) {
        (IERC20[] memory tokens, , uint256[] memory poolBalances, ) = vault.getPoolTokenInfo(pool);
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 currentToken = tokens[i];
            if (currentToken == dai) {
                balances.dai = poolBalances[i];
            } else if (currentToken == weth) {
                balances.weth = poolBalances[i];
            } else if (currentToken == wsteth) {
                balances.wsteth = poolBalances[i];
            } else if (currentToken == usdc) {
                balances.usdc = poolBalances[i];
            } else if (currentToken == IERC20(childPoolA)) {
                balances.childPoolABpt = poolBalances[i];
            } else if (currentToken == IERC20(childPoolB)) {
                balances.childPoolBBpt = poolBalances[i];
            }
        }

        balances.totalSupply = BalancerPoolToken(pool).totalSupply();
    }
}
