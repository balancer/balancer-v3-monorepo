// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { ICompositeLiquidityRouter } from "@balancer-labs/v3-interfaces/contracts/vault/ICompositeLiquidityRouter.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { BalancerPoolToken } from "../../contracts/BalancerPoolToken.sol";
import { BaseERC4626BufferTest } from "./utils/BaseERC4626BufferTest.sol";

contract CompositeLiquidityRouterNestedPoolsTest is BaseERC4626BufferTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    address internal parentPool;
    address internal childPoolA;
    address internal childPoolB;

    address internal childPoolERC4626;
    address internal parentPoolWithoutWrapper;
    address internal parentPoolWithWrapper;

    // Max of 5 wei of error when retrieving tokens from a nested pool.
    uint256 internal constant MAX_ROUND_ERROR = 5;

    function setUp() public override {
        BaseERC4626BufferTest.setUp();

        childPoolA = _createPool([address(usdc), address(weth)].toMemoryArray(), "childPoolA");
        childPoolB = _createPool([address(wsteth), address(dai)].toMemoryArray(), "childPoolB");
        parentPool = _createPool(
            [address(childPoolA), address(childPoolB), address(dai)].toMemoryArray(),
            "parentPool"
        );

        childPoolERC4626 = _createPool([address(waDAI), address(weth)].toMemoryArray(), "childPoolERC4626");
        parentPoolWithoutWrapper = _createPool(
            [address(childPoolERC4626), address(usdc)].toMemoryArray(),
            "parentPoolWithoutWrapper"
        );
        parentPoolWithWrapper = _createPool(
            [address(childPoolERC4626), address(waUSDC)].toMemoryArray(),
            "parentPoolWithWrapper"
        );

        approveForPool(IERC20(childPoolA));
        approveForPool(IERC20(childPoolB));
        approveForPool(IERC20(childPoolERC4626));

        approveForPool(IERC20(parentPool));
        approveForPool(IERC20(parentPoolWithoutWrapper));
        approveForPool(IERC20(parentPoolWithWrapper));

        vm.startPrank(lp);
        uint256 childPoolABptOut = _initPool(childPoolA, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        uint256 childPoolBBptOut = _initPool(childPoolB, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        // Initialize the ERC4626 child pool with 2x poolInitAmount, because we will split the BPTs into two pools. So,
        // it'll be easier to calculate the expectedAmountOut on removeLiquidity.
        uint256 childPoolERC4626BptOut = _initPool(
            childPoolERC4626,
            [2 * poolInitAmount, 2 * poolInitAmount].toMemoryArray(),
            0
        );

        _initPoolUnsorted(
            parentPool,
            [childPoolA, childPoolB, address(dai)].toMemoryArray(),
            [childPoolABptOut, childPoolBBptOut, poolInitAmount].toMemoryArray()
        );
        _initPoolUnsorted(
            parentPoolWithoutWrapper,
            [childPoolERC4626, address(usdc)].toMemoryArray(),
            [childPoolERC4626BptOut / 2, poolInitAmount].toMemoryArray()
        );
        _initPoolUnsorted(
            parentPoolWithWrapper,
            [childPoolERC4626, address(waUSDC)].toMemoryArray(),
            [childPoolERC4626BptOut / 2, poolInitAmount].toMemoryArray()
        );
        vm.stopPrank();
    }

    function _initPoolUnsorted(
        address poolToInitialize,
        address[] memory unsortedTokensIn,
        uint256[] memory unsortedAmountsIn
    ) private {
        uint256[] memory tokenIndexes = getSortedIndexes(unsortedTokensIn);

        uint256[] memory sortedAmountsIn = new uint256[](unsortedTokensIn.length);
        for (uint256 i = 0; i < unsortedTokensIn.length; i++) {
            sortedAmountsIn[tokenIndexes[i]] = unsortedAmountsIn[i];
        }

        _initPool(poolToInitialize, sortedAmountsIn, 0);
    }

    /*******************************************************************************
                                Add liquidity
    *******************************************************************************/

    function testAddLiquidityNestedPool__Fuzz(
        uint256 daiAmount,
        uint256 usdcAmount,
        uint256 wethAmount,
        uint256 wstEthAmount
    ) public {
        daiAmount = bound(daiAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);
        usdcAmount = bound(usdcAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);
        wethAmount = bound(wethAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);
        wstEthAmount = bound(wstEthAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);

        uint256 minBptOut = 0;

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

        // Check exact BPT out.
        // Since all pools are linear and there's no rate, the expected BPT amount out is the sum of all amounts in.
        uint256 expectedBptOut = daiAmount + usdcAmount + wethAmount + wstEthAmount;
        assertApproxEqAbs(exactBptOut, expectedBptOut, 10, "Exact BPT amount out is wrong");
        assertLt(exactBptOut, expectedBptOut, "BPT out rounding direction is wrong");

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

    function testAddLiquidityNestedERC4626WithUnderlying__Fuzz(
        uint256 daiAmount,
        uint256 usdcAmount,
        uint256 wethAmount
    ) public {
        daiAmount = bound(daiAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);
        usdcAmount = bound(usdcAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);
        wethAmount = bound(wethAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);

        uint256 minBptOut = 0;

        NestedPoolTestLocals memory vars = _createNestedPoolTestLocals();
        // Override indexes, since wstEth is not used in this test.
        vars.daiIdx = 0;
        vars.usdcIdx = 1;
        vars.wethIdx = 2;

        address[] memory tokensIn = new address[](3);
        tokensIn[vars.daiIdx] = address(dai);
        tokensIn[vars.usdcIdx] = address(usdc);
        tokensIn[vars.wethIdx] = address(weth);

        uint256[] memory amountsIn = new uint256[](3);
        amountsIn[vars.daiIdx] = daiAmount;
        amountsIn[vars.usdcIdx] = usdcAmount;
        amountsIn[vars.wethIdx] = wethAmount;

        vm.prank(lp);
        uint256 exactBptOut = compositeLiquidityRouter.addLiquidityUnbalancedNestedPool(
            parentPoolWithoutWrapper,
            tokensIn,
            amountsIn,
            minBptOut,
            bytes("")
        );

        _fillNestedPoolTestLocalsAfter(vars);
        uint256 mintedChildPoolERC4626Bpts = vars.childPoolERC4626After.totalSupply -
            vars.childPoolERC4626Before.totalSupply;

        // Check exact BPT out.
        // Since all pools are linear and there's no rate, the expected BPT amount out is the sum of all amounts in.
        uint256 expectedBptOut = waDAI.previewDeposit(daiAmount) + usdcAmount + wethAmount;
        assertApproxEqAbs(exactBptOut, expectedBptOut, 10, "Exact BPT amount out is wrong");
        assertLt(exactBptOut, expectedBptOut, "BPT out rounding direction is wrong");

        // Check LP Balances.
        assertEq(vars.lpAfter.dai, vars.lpBefore.dai - amountsIn[vars.daiIdx], "LP Dai Balance is wrong");
        assertEq(vars.lpAfter.weth, vars.lpBefore.weth - amountsIn[vars.wethIdx], "LP Weth Balance is wrong");
        assertEq(vars.lpAfter.usdc, vars.lpBefore.usdc - amountsIn[vars.usdcIdx], "LP Usdc Balance is wrong");
        assertEq(
            vars.lpAfter.childPoolERC4626Bpt,
            vars.lpBefore.childPoolERC4626Bpt,
            "LP ChildPoolERC4626 BPT Balance is wrong"
        );
        assertEq(
            vars.lpAfter.parentPoolWithoutWrapperBpt,
            vars.lpBefore.parentPoolWithoutWrapperBpt + exactBptOut,
            "LP ParentPoolWithoutWrapper BPT Balance is wrong"
        );

        // Check Vault Balances. Since the buffer has enough balance, the Vault only increased its underlying tokens.
        assertEq(vars.vaultAfter.dai, vars.vaultBefore.dai + amountsIn[vars.daiIdx], "Vault Dai Balance is wrong");
        assertEq(vars.vaultAfter.waDAI, vars.vaultBefore.waDAI, "Vault waDai Balance is wrong");
        assertEq(vars.vaultAfter.weth, vars.vaultBefore.weth + amountsIn[vars.wethIdx], "Vault Weth Balance is wrong");
        assertEq(vars.vaultAfter.usdc, vars.vaultBefore.usdc + amountsIn[vars.usdcIdx], "Vault Usdc Balance is wrong");
        assertEq(vars.vaultAfter.waUSDC, vars.vaultBefore.waUSDC, "Vault waUsdc Balance is wrong");
        // Since all Child Pool BPTs were allocated in the parent pool, vault is holding all of the minted BPTs.
        assertEq(
            vars.vaultAfter.childPoolERC4626Bpt,
            vars.vaultBefore.childPoolERC4626Bpt + mintedChildPoolERC4626Bpts,
            "Vault ChildPoolERC4626 BPT Balance is wrong"
        );

        // Vault's parent pool BPTs did not change.
        assertEq(
            vars.vaultAfter.parentPoolWithoutWrapperBpt,
            vars.vaultBefore.parentPoolWithoutWrapperBpt,
            "Vault ParentPoolWithoutWrapper BPT Balance is wrong"
        );

        // Check ChildPoolERC4626 balances.
        assertEq(
            vars.childPoolERC4626After.waDAI,
            vars.childPoolERC4626Before.waDAI + waDAI.previewDeposit(amountsIn[vars.daiIdx]),
            "ChildPoolERC4626 waDAI Balance is wrong"
        );
        assertEq(
            vars.childPoolERC4626After.weth,
            vars.childPoolERC4626Before.weth + amountsIn[vars.wethIdx],
            "ChildPoolERC4626 WETH Balance is wrong"
        );

        // Check ParentPoolWithoutWrapper balances.
        assertEq(
            vars.parentPoolWithoutWrapperAfter.childPoolERC4626Bpt,
            vars.parentPoolWithoutWrapperBefore.childPoolERC4626Bpt + mintedChildPoolERC4626Bpts,
            "ParentPoolWithoutWrapper ChildPoolERC4626 BPT Balance is wrong"
        );
        assertEq(
            vars.parentPoolWithoutWrapperAfter.usdc,
            vars.parentPoolWithoutWrapperBefore.usdc + amountsIn[vars.usdcIdx],
            "ParentPoolWithoutWrapper USDC Balance is wrong"
        );
    }

    function testAddLiquidityNestedERC4626WithWrapped__Fuzz(
        uint256 waDaiAmount,
        uint256 usdcAmount,
        uint256 wethAmount
    ) public {
        waDaiAmount = bound(waDaiAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);
        usdcAmount = bound(usdcAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);
        wethAmount = bound(wethAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);

        uint256 minBptOut = 0;

        NestedPoolTestLocals memory vars = _createNestedPoolTestLocals();
        // Override indexes, since wstEth is not used in this test.
        vars.waDaiIdx = 0;
        vars.usdcIdx = 1;
        vars.wethIdx = 2;

        address[] memory tokensIn = new address[](3);
        tokensIn[vars.waDaiIdx] = address(waDAI);
        tokensIn[vars.usdcIdx] = address(usdc);
        tokensIn[vars.wethIdx] = address(weth);

        uint256[] memory amountsIn = new uint256[](3);
        amountsIn[vars.waDaiIdx] = waDaiAmount;
        amountsIn[vars.usdcIdx] = usdcAmount;
        amountsIn[vars.wethIdx] = wethAmount;

        vm.prank(lp);
        uint256 exactBptOut = compositeLiquidityRouter.addLiquidityUnbalancedNestedPool(
            parentPoolWithoutWrapper,
            tokensIn,
            amountsIn,
            minBptOut,
            bytes("")
        );

        _fillNestedPoolTestLocalsAfter(vars);
        uint256 mintedChildPoolERC4626Bpts = vars.childPoolERC4626After.totalSupply -
            vars.childPoolERC4626Before.totalSupply;

        // Check exact BPT out.
        // Since all pools are linear and there's no rate, the expected BPT amount out is the sum of all amounts in.
        uint256 expectedBptOut = waDaiAmount + usdcAmount + wethAmount;
        assertApproxEqAbs(exactBptOut, expectedBptOut, 10, "Exact BPT amount out is wrong");
        assertLt(exactBptOut, expectedBptOut, "BPT out rounding direction is wrong");

        // Check LP Balances.
        // Since LP passed the wrapper address as a token in, his DAI balance is not touched.
        assertEq(vars.lpAfter.dai, vars.lpBefore.dai, "LP Dai Balance is wrong");
        assertEq(vars.lpAfter.waDAI, vars.lpBefore.waDAI - amountsIn[vars.waDaiIdx], "LP waDAI Balance is wrong");
        assertEq(vars.lpAfter.weth, vars.lpBefore.weth - amountsIn[vars.wethIdx], "LP Weth Balance is wrong");
        assertEq(vars.lpAfter.usdc, vars.lpBefore.usdc - amountsIn[vars.usdcIdx], "LP Usdc Balance is wrong");
        assertEq(
            vars.lpAfter.childPoolERC4626Bpt,
            vars.lpBefore.childPoolERC4626Bpt,
            "LP ChildPoolERC4626 BPT Balance is wrong"
        );
        assertEq(
            vars.lpAfter.parentPoolWithoutWrapperBpt,
            vars.lpBefore.parentPoolWithoutWrapperBpt + exactBptOut,
            "LP ParentPoolWithoutWrapper BPT Balance is wrong"
        );

        // Check Vault Balances.
        assertEq(vars.vaultAfter.dai, vars.vaultBefore.dai, "Vault Dai Balance is wrong");
        assertEq(
            vars.vaultAfter.waDAI,
            vars.vaultBefore.waDAI + amountsIn[vars.waDaiIdx],
            "Vault waDAI Balance is wrong"
        );
        assertEq(vars.vaultAfter.weth, vars.vaultBefore.weth + amountsIn[vars.wethIdx], "Vault Weth Balance is wrong");
        assertEq(vars.vaultAfter.usdc, vars.vaultBefore.usdc + amountsIn[vars.usdcIdx], "Vault Usdc Balance is wrong");
        // Since all Child Pool BPTs were allocated in the parent pool, vault is holding all of the minted BPTs.
        assertEq(
            vars.vaultAfter.childPoolERC4626Bpt,
            vars.vaultBefore.childPoolERC4626Bpt + mintedChildPoolERC4626Bpts,
            "Vault ChildPoolERC4626 BPT Balance is wrong"
        );

        // Vault's parent pool BPTs did not change.
        assertEq(
            vars.vaultAfter.parentPoolWithoutWrapperBpt,
            vars.vaultBefore.parentPoolWithoutWrapperBpt,
            "Vault ParentPoolWithoutWrapper BPT Balance is wrong"
        );

        // Check ChildPoolERC4626 balances.
        assertEq(
            vars.childPoolERC4626After.waDAI,
            vars.childPoolERC4626Before.waDAI + amountsIn[vars.waDaiIdx],
            "ChildPoolERC4626 waDAI Balance is wrong"
        );
        assertEq(
            vars.childPoolERC4626After.weth,
            vars.childPoolERC4626Before.weth + amountsIn[vars.wethIdx],
            "ChildPoolERC4626 WETH Balance is wrong"
        );

        // Check ParentPoolWithoutWrapper balances.
        assertEq(
            vars.parentPoolWithoutWrapperAfter.childPoolERC4626Bpt,
            vars.parentPoolWithoutWrapperBefore.childPoolERC4626Bpt + mintedChildPoolERC4626Bpts,
            "ParentPoolWithoutWrapper ChildPoolERC4626 BPT Balance is wrong"
        );
        assertEq(
            vars.parentPoolWithoutWrapperAfter.usdc,
            vars.parentPoolWithoutWrapperBefore.usdc + amountsIn[vars.usdcIdx],
            "ParentPoolWithoutWrapper USDC Balance is wrong"
        );
    }

    function testAddLiquidityNestedERC4626InParentWithUnderlying__Fuzz(
        uint256 daiAmount,
        uint256 usdcAmount,
        uint256 wethAmount
    ) public {
        daiAmount = bound(daiAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);
        usdcAmount = bound(usdcAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);
        wethAmount = bound(wethAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);

        uint256 minBptOut = 0;

        NestedPoolTestLocals memory vars = _createNestedPoolTestLocals();
        // Override indexes, since wstEth is not used in this test.
        vars.daiIdx = 0;
        vars.usdcIdx = 1;
        vars.wethIdx = 2;

        address[] memory tokensIn = new address[](3);
        tokensIn[vars.daiIdx] = address(dai);
        tokensIn[vars.usdcIdx] = address(usdc);
        tokensIn[vars.wethIdx] = address(weth);

        uint256[] memory amountsIn = new uint256[](3);
        amountsIn[vars.daiIdx] = daiAmount;
        amountsIn[vars.usdcIdx] = usdcAmount;
        amountsIn[vars.wethIdx] = wethAmount;

        vm.prank(lp);
        uint256 exactBptOut = compositeLiquidityRouter.addLiquidityUnbalancedNestedPool(
            parentPoolWithWrapper,
            tokensIn,
            amountsIn,
            minBptOut,
            bytes("")
        );

        _fillNestedPoolTestLocalsAfter(vars);
        uint256 mintedChildPoolERC4626Bpts = vars.childPoolERC4626After.totalSupply -
            vars.childPoolERC4626Before.totalSupply;

        // Check exact BPT out.
        // Since all pools are linear and there's no rate, the expected BPT amount out is the sum of all amounts in.
        uint256 expectedBptOut = waDAI.previewDeposit(daiAmount) + waUSDC.previewDeposit(usdcAmount) + wethAmount;
        assertApproxEqAbs(exactBptOut, expectedBptOut, 10, "Exact BPT amount out is wrong");
        assertLt(exactBptOut, expectedBptOut, "BPT out rounding direction is wrong");

        // Check LP Balances.
        assertEq(vars.lpAfter.dai, vars.lpBefore.dai - amountsIn[vars.daiIdx], "LP Dai Balance is wrong");
        assertEq(vars.lpAfter.weth, vars.lpBefore.weth - amountsIn[vars.wethIdx], "LP Weth Balance is wrong");
        assertEq(vars.lpAfter.usdc, vars.lpBefore.usdc - amountsIn[vars.usdcIdx], "LP Usdc Balance is wrong");
        assertEq(
            vars.lpAfter.childPoolERC4626Bpt,
            vars.lpBefore.childPoolERC4626Bpt,
            "LP ChildPoolERC4626 BPT Balance is wrong"
        );
        assertEq(
            vars.lpAfter.parentPoolWithWrapperBpt,
            vars.lpBefore.parentPoolWithWrapperBpt + exactBptOut,
            "LP ParentPoolWithWrapper BPT Balance is wrong"
        );

        // Check Vault Balances. Since the buffer has enough balance, the Vault only increased its underlying tokens.
        assertEq(vars.vaultAfter.dai, vars.vaultBefore.dai + amountsIn[vars.daiIdx], "Vault Dai Balance is wrong");
        assertEq(vars.vaultAfter.waDAI, vars.vaultBefore.waDAI, "Vault waDai Balance is wrong");
        assertEq(vars.vaultAfter.weth, vars.vaultBefore.weth + amountsIn[vars.wethIdx], "Vault Weth Balance is wrong");
        assertEq(vars.vaultAfter.usdc, vars.vaultBefore.usdc + amountsIn[vars.usdcIdx], "Vault Usdc Balance is wrong");
        assertEq(vars.vaultAfter.waUSDC, vars.vaultBefore.waUSDC, "Vault waUSDC Balance is wrong");

        // Since all Child Pool BPTs were allocated in the parent pool, vault is holding all of the minted BPTs.
        assertEq(
            vars.vaultAfter.childPoolERC4626Bpt,
            vars.vaultBefore.childPoolERC4626Bpt + mintedChildPoolERC4626Bpts,
            "Vault ChildPoolERC4626 BPT Balance is wrong"
        );

        // Vault's parent pool BPTs did not change.
        assertEq(
            vars.vaultAfter.parentPoolWithWrapperBpt,
            vars.vaultBefore.parentPoolWithWrapperBpt,
            "Vault ParentPoolWithWrapper BPT Balance is wrong"
        );

        // Check ChildPoolERC4626 balances.
        assertEq(
            vars.childPoolERC4626After.waDAI,
            vars.childPoolERC4626Before.waDAI + waDAI.previewDeposit(amountsIn[vars.daiIdx]),
            "ChildPoolERC4626 waDAI Balance is wrong"
        );
        assertEq(
            vars.childPoolERC4626After.weth,
            vars.childPoolERC4626Before.weth + amountsIn[vars.wethIdx],
            "ChildPoolERC4626 WETH Balance is wrong"
        );

        // Check ParentPoolWithoutWrapper balances.
        assertEq(
            vars.parentPoolWithWrapperAfter.childPoolERC4626Bpt,
            vars.parentPoolWithWrapperBefore.childPoolERC4626Bpt + mintedChildPoolERC4626Bpts,
            "ParentPoolWithWrapper ChildPoolERC4626 BPT Balance is wrong"
        );
        assertEq(
            vars.parentPoolWithWrapperAfter.waUSDC,
            vars.parentPoolWithWrapperBefore.waUSDC + waUSDC.previewDeposit(amountsIn[vars.usdcIdx]),
            "ParentPoolWithWrapper waUSDC Balance is wrong"
        );
    }

    function testAddLiquidityNestedERC4626InParentWithWrapped__Fuzz(
        uint256 waDaiAmount,
        uint256 waUsdcAmount,
        uint256 wethAmount
    ) public {
        waDaiAmount = bound(waDaiAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);
        waUsdcAmount = bound(waUsdcAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);
        wethAmount = bound(wethAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);

        uint256 minBptOut = 0;

        NestedPoolTestLocals memory vars = _createNestedPoolTestLocals();
        // Override indexes, since wstEth is not used in this test.
        vars.waDaiIdx = 0;
        vars.waUsdcIdx = 1;
        vars.wethIdx = 2;

        address[] memory tokensIn = new address[](3);
        tokensIn[vars.waDaiIdx] = address(waDAI);
        tokensIn[vars.waUsdcIdx] = address(waUSDC);
        tokensIn[vars.wethIdx] = address(weth);

        uint256[] memory amountsIn = new uint256[](3);
        amountsIn[vars.waDaiIdx] = waDaiAmount;
        amountsIn[vars.waUsdcIdx] = waUsdcAmount;
        amountsIn[vars.wethIdx] = wethAmount;

        vm.prank(lp);
        uint256 exactBptOut = compositeLiquidityRouter.addLiquidityUnbalancedNestedPool(
            parentPoolWithWrapper,
            tokensIn,
            amountsIn,
            minBptOut,
            bytes("")
        );

        _fillNestedPoolTestLocalsAfter(vars);
        uint256 mintedChildPoolERC4626Bpts = vars.childPoolERC4626After.totalSupply -
            vars.childPoolERC4626Before.totalSupply;

        // Check exact BPT out.
        // Since all pools are linear and there's no rate, the expected BPT amount out is the sum of all amounts in.
        uint256 expectedBptOut = waDaiAmount + waUsdcAmount + wethAmount;
        assertApproxEqAbs(exactBptOut, expectedBptOut, 10, "Exact BPT amount out is wrong");
        assertLt(exactBptOut, expectedBptOut, "BPT out rounding direction is wrong");

        // Check LP Balances.
        // Since LP passed the wrapper address as a token in, his DAI and USDC balances are not touched.
        assertEq(vars.lpAfter.dai, vars.lpBefore.dai, "LP Dai Balance is wrong");
        assertEq(vars.lpAfter.usdc, vars.lpBefore.usdc, "LP USDC Balance is wrong");
        assertEq(vars.lpAfter.waDAI, vars.lpBefore.waDAI - amountsIn[vars.waDaiIdx], "LP waDAI Balance is wrong");
        assertEq(vars.lpAfter.waUSDC, vars.lpBefore.waUSDC - amountsIn[vars.waUsdcIdx], "LP waUSDC Balance is wrong");
        assertEq(vars.lpAfter.weth, vars.lpBefore.weth - amountsIn[vars.wethIdx], "LP Weth Balance is wrong");
        assertEq(
            vars.lpAfter.childPoolERC4626Bpt,
            vars.lpBefore.childPoolERC4626Bpt,
            "LP ChildPoolERC4626 BPT Balance is wrong"
        );
        assertEq(
            vars.lpAfter.parentPoolWithWrapperBpt,
            vars.lpBefore.parentPoolWithWrapperBpt + exactBptOut,
            "LP ParentPoolWithWrapper BPT Balance is wrong"
        );

        // Check Vault Balances.
        assertEq(vars.vaultAfter.dai, vars.vaultBefore.dai, "Vault Dai Balance is wrong");
        assertEq(vars.vaultAfter.usdc, vars.vaultBefore.usdc, "Vault USDC Balance is wrong");
        assertEq(
            vars.vaultAfter.waDAI,
            vars.vaultBefore.waDAI + amountsIn[vars.waDaiIdx],
            "Vault waDAI Balance is wrong"
        );
        assertEq(
            vars.vaultAfter.waUSDC,
            vars.vaultBefore.waUSDC + amountsIn[vars.waUsdcIdx],
            "Vault waDAI Balance is wrong"
        );
        assertEq(vars.vaultAfter.weth, vars.vaultBefore.weth + amountsIn[vars.wethIdx], "Vault Weth Balance is wrong");
        // Since all Child Pool BPTs were allocated in the parent pool, vault is holding all of the minted BPTs.
        assertEq(
            vars.vaultAfter.childPoolERC4626Bpt,
            vars.vaultBefore.childPoolERC4626Bpt + mintedChildPoolERC4626Bpts,
            "Vault ChildPoolERC4626 BPT Balance is wrong"
        );

        // Vault's parent pool BPTs did not change.
        assertEq(
            vars.vaultAfter.parentPoolWithWrapperBpt,
            vars.vaultBefore.parentPoolWithWrapperBpt,
            "Vault ParentPoolWithWrapper BPT Balance is wrong"
        );

        // Check ChildPoolERC4626 balances.
        assertEq(
            vars.childPoolERC4626After.waDAI,
            vars.childPoolERC4626Before.waDAI + amountsIn[vars.waDaiIdx],
            "ChildPoolERC4626 waDAI Balance is wrong"
        );
        assertEq(
            vars.childPoolERC4626After.weth,
            vars.childPoolERC4626Before.weth + amountsIn[vars.wethIdx],
            "ChildPoolERC4626 WETH Balance is wrong"
        );

        // Check ParentPoolWithWrapper balances.
        assertEq(
            vars.parentPoolWithWrapperAfter.childPoolERC4626Bpt,
            vars.parentPoolWithWrapperBefore.childPoolERC4626Bpt + mintedChildPoolERC4626Bpts,
            "ParentPoolWithWrapper ChildPoolERC4626 BPT Balance is wrong"
        );
        assertEq(
            vars.parentPoolWithWrapperAfter.waUSDC,
            vars.parentPoolWithWrapperBefore.waUSDC + amountsIn[vars.waUsdcIdx],
            "ParentPoolWithWrapper waUSDC Balance is wrong"
        );
    }

    function testQueryAddLiquidityNestedERC4626__Fuzz(
        uint256 daiAmount,
        uint256 usdcAmount,
        uint256 wethAmount
    ) public {
        daiAmount = bound(daiAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);
        usdcAmount = bound(usdcAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);
        wethAmount = bound(wethAmount, PRODUCTION_MIN_TRADE_AMOUNT, 10 * poolInitAmount);

        uint256 minBptOut = 0;

        NestedPoolTestLocals memory vars = _createNestedPoolTestLocals();
        // Override indexes, since wstEth is not used in this test.
        vars.daiIdx = 0;
        vars.usdcIdx = 1;
        vars.wethIdx = 2;

        address[] memory tokensIn = new address[](3);
        tokensIn[vars.daiIdx] = address(dai);
        tokensIn[vars.usdcIdx] = address(usdc);
        tokensIn[vars.wethIdx] = address(weth);

        uint256[] memory amountsIn = new uint256[](3);
        amountsIn[vars.daiIdx] = daiAmount;
        amountsIn[vars.usdcIdx] = usdcAmount;
        amountsIn[vars.wethIdx] = wethAmount;

        _prankStaticCall();
        uint256 queryBptOut = compositeLiquidityRouter.queryAddLiquidityUnbalancedNestedPool(
            parentPoolWithWrapper,
            tokensIn,
            amountsIn,address(this),
            bytes("")
        );

        vm.prank(lp);
        uint256 exactBptOut = compositeLiquidityRouter.addLiquidityUnbalancedNestedPool(
            parentPoolWithWrapper,
            tokensIn,
            amountsIn,
            minBptOut,
            bytes("")
        );

        // The actual `addLiquidity` changes rates of the wrappers when performing intermediate wrap / unwrap states,
        // whereas `query` does not. Then, the final steps of the query are computed based off different values
        // wrt. the actual operation, which in turn produces a different result. In general, the wrappers will round
        // in their favor, so the query should produce a result that is more favorable to the user than the actual
        // operation.
        assertApproxEqAbs(exactBptOut, queryBptOut, 10, "BPTs out do not match");
        assertLt(exactBptOut, queryBptOut, "Wrapper rounding direction is incorrect");
    }

    function testAddLiquidityNestedPoolMissingToken() public {
        uint256 daiAmount = poolInitAmount;
        uint256 usdcAmount = poolInitAmount;
        uint256 wethAmount = poolInitAmount;
        // WstETH token won't be added to the Add Liquidity Unbalanced, but the operation should succeed.

        uint256 minBptOut = 0;

        NestedPoolTestLocals memory vars = _createNestedPoolTestLocals();
        vars.daiIdx = 0;
        vars.usdcIdx = 1;
        vars.wethIdx = 2;

        address[] memory tokensIn = new address[](3);
        tokensIn[vars.daiIdx] = address(dai);
        tokensIn[vars.usdcIdx] = address(usdc);
        tokensIn[vars.wethIdx] = address(weth);

        uint256[] memory amountsIn = new uint256[](3);
        amountsIn[vars.daiIdx] = daiAmount;
        amountsIn[vars.usdcIdx] = usdcAmount;
        amountsIn[vars.wethIdx] = wethAmount;

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

        // Check exact BPT out.
        // Since all pools are linear and there's no rate, the expected BPT amount out is the sum of all amounts in.
        uint256 expectedBptOut = daiAmount + usdcAmount + wethAmount;
        assertApproxEqAbs(exactBptOut, expectedBptOut, 10, "Exact BPT amount out is wrong");
        assertLt(exactBptOut, expectedBptOut, "BPT out rounding direction is wrong");

        // Check LP Balances.
        assertEq(vars.lpAfter.dai, vars.lpBefore.dai - amountsIn[vars.daiIdx], "LP Dai Balance is wrong");
        assertEq(vars.lpAfter.weth, vars.lpBefore.weth - amountsIn[vars.wethIdx], "LP Weth Balance is wrong");
        // WstETH is the missing token, so its amount does not change.
        assertEq(vars.lpAfter.wsteth, vars.lpBefore.wsteth, "LP Wsteth Balance is wrong");
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
        assertEq(vars.vaultAfter.wsteth, vars.vaultBefore.wsteth, "Vault Wsteth Balance is wrong");
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
        assertEq(vars.childPoolBAfter.wsteth, vars.childPoolBBefore.wsteth, "ChildPoolB Wsteth Balance is wrong");

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

    function testAddLiquidityNestedPoolBptLimit() public {
        uint256 daiAmount = poolInitAmount;
        uint256 usdcAmount = poolInitAmount;
        uint256 wethAmount = poolInitAmount;
        uint256 wstEthAmount = poolInitAmount;

        // Since all pools are linear and there's no rate, the expected BPT amount out is the sum of all amounts in
        // minus rounding.
        uint256 expectedBptOut = daiAmount + usdcAmount + wethAmount + wstEthAmount - 7;
        uint256 minBptOut = 10 * poolInitAmount;

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
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BptAmountOutBelowMin.selector, expectedBptOut, minBptOut));
        compositeLiquidityRouter.addLiquidityUnbalancedNestedPool(
            parentPool,
            tokensIn,
            amountsIn,
            minBptOut,
            bytes("")
        );
    }

    function testAddLiquidityNestedPoolWrongTokenArray() public {
        uint256 daiAmount = poolInitAmount;
        uint256 usdcAmount = poolInitAmount;
        uint256 wethAmount = poolInitAmount;
        uint256 wstEthAmount = poolInitAmount;

        uint256 minBptOut = 0;

        NestedPoolTestLocals memory vars = _createNestedPoolTestLocals();

        address[] memory tokensIn = new address[](3);
        tokensIn[0] = address(dai);
        tokensIn[1] = address(usdc);
        tokensIn[2] = address(weth);

        uint256[] memory amountsIn = new uint256[](4);
        amountsIn[vars.daiIdx] = daiAmount;
        amountsIn[vars.usdcIdx] = usdcAmount;
        amountsIn[vars.wethIdx] = wethAmount;
        amountsIn[vars.wstethIdx] = wstEthAmount;

        vm.prank(lp);
        // Since tokensIn and amountsIn have different lengths, revert.
        vm.expectRevert(InputHelpers.InputLengthMismatch.selector);
        compositeLiquidityRouter.addLiquidityUnbalancedNestedPool(
            parentPool,
            tokensIn,
            amountsIn,
            minBptOut,
            bytes("")
        );
    }

    function testAddLiquidityNestedPoolNonExistentToken() public {
        ERC20TestToken newToken = new ERC20TestToken("New Token", "NT", 18);

        uint256 daiAmount = poolInitAmount;
        uint256 usdcAmount = poolInitAmount;
        uint256 wethAmount = poolInitAmount;
        uint256 wstEthAmount = poolInitAmount;
        uint256 newTokenAmount = poolInitAmount;

        uint256 minBptOut = 0;

        NestedPoolTestLocals memory vars = _createNestedPoolTestLocals();

        address[] memory tokensIn = new address[](5);
        tokensIn[vars.daiIdx] = address(dai);
        tokensIn[vars.usdcIdx] = address(usdc);
        tokensIn[vars.wethIdx] = address(weth);
        tokensIn[vars.wstethIdx] = address(wsteth);
        tokensIn[4] = address(newToken);

        uint256[] memory amountsIn = new uint256[](5);
        amountsIn[vars.daiIdx] = daiAmount;
        amountsIn[vars.usdcIdx] = usdcAmount;
        amountsIn[vars.wethIdx] = wethAmount;
        amountsIn[vars.wstethIdx] = wstEthAmount;
        amountsIn[4] = newTokenAmount;

        vm.startPrank(lp);
        // Mints amount to LP, so it can pay for the transaction in the router.
        newToken.mint(lp, poolInitAmount);
        // Allow permit2 to move newToken amounts from sender to the router.
        newToken.approve(address(permit2), type(uint256).max);
        permit2.approve(address(newToken), address(compositeLiquidityRouter), type(uint160).max, type(uint48).max);
        // Since user passed a token that was not deposited in any pool, transaction reverts.
        vm.expectRevert(IVaultErrors.BalanceNotSettled.selector);
        compositeLiquidityRouter.addLiquidityUnbalancedNestedPool(
            parentPool,
            tokensIn,
            amountsIn,
            minBptOut,
            bytes("")
        );
        vm.stopPrank();
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
        // them was burned when liquidity was removed, we need to discount this amount from the Vault reserves.
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

        // Check ChildPoolB.
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

        // Check ParentPool.
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

    function testRemoveLiquidityNestedERC4626Pool__Fuzz(uint256 proportionToRemove) public {
        // Remove between 0.0001% and 50% of each pool liquidity.
        proportionToRemove = bound(proportionToRemove, 1e12, 50e16);

        uint256 totalPoolBPTs = BalancerPoolToken(parentPoolWithWrapper).totalSupply();
        // Since LP is the owner of all BPT supply, and part of the BPTs were burned in the initialization step, using
        // totalSupply is more accurate to remove exactly the proportion that we intend from each pool.
        uint256 exactBptIn = totalPoolBPTs.mulDown(proportionToRemove);

        NestedPoolTestLocals memory vars = _createNestedPoolTestLocals();
        // Override indexes, since wstEth is not used in this test.
        vars.daiIdx = 0;
        vars.usdcIdx = 1;
        vars.wethIdx = 2;

        // During pool initialization, POOL_MINIMUM_TOTAL_SUPPLY amount of BPT is burned to address(0), so that the
        // pool cannot be completely drained. We need to discount this amount of tokens from the total liquidity that
        // we can extract from the child pools.
        uint256 deadTokens = (POOL_MINIMUM_TOTAL_SUPPLY / 4).mulDown(proportionToRemove);

        address[] memory tokensOut = new address[](3);
        tokensOut[vars.daiIdx] = address(dai);
        tokensOut[vars.wethIdx] = address(weth);
        tokensOut[vars.usdcIdx] = address(usdc);

        uint256[] memory expectedAmountsOut = new uint256[](3);
        // Since pools are in their initial state, we can use poolInitAmount as the balance of each token in the pool.
        // Also, we only need to account for deadTokens once, since we calculate the BPT in for the parent pool using
        // totalSupply (so the burned POOL_MINIMUM_TOTAL_SUPPLY amount does not affect the BPT in circulation, and the
        // amounts out are perfectly proportional to the parent pool balance).
        expectedAmountsOut[vars.daiIdx] = waDAI.previewRedeem(
            poolInitAmount.mulDown(proportionToRemove) - deadTokens - MAX_ROUND_ERROR
        );
        expectedAmountsOut[vars.wethIdx] = poolInitAmount.mulDown(proportionToRemove) - deadTokens - MAX_ROUND_ERROR;
        expectedAmountsOut[vars.usdcIdx] = waUSDC.previewRedeem(
            poolInitAmount.mulDown(proportionToRemove) - MAX_ROUND_ERROR
        );

        vm.prank(lp);
        uint256[] memory amountsOut = compositeLiquidityRouter.removeLiquidityProportionalNestedPool(
            parentPoolWithWrapper,
            exactBptIn,
            tokensOut,
            expectedAmountsOut,
            bytes("")
        );

        _fillNestedPoolTestLocalsAfter(vars);
        uint256 burnedChildPoolERC4626Bpts = vars.childPoolERC4626Before.totalSupply -
            vars.childPoolERC4626After.totalSupply;

        // Check returned token amounts.
        assertEq(amountsOut.length, 3, "amountsOut length is wrong");
        assertApproxEqAbs(
            expectedAmountsOut[vars.daiIdx],
            amountsOut[vars.daiIdx],
            6 * MAX_ROUND_ERROR, // Increasing error because of ERC4626 conversion roundings
            "DAI amount out is wrong"
        );
        assertApproxEqAbs(
            expectedAmountsOut[vars.wethIdx],
            amountsOut[vars.wethIdx],
            6 * MAX_ROUND_ERROR, // Increasing error because of ERC4626 conversion roundings
            "WETH amount out is wrong"
        );
        assertApproxEqAbs(
            expectedAmountsOut[vars.usdcIdx],
            amountsOut[vars.usdcIdx],
            6 * MAX_ROUND_ERROR, // Increasing error because of ERC4626 conversion roundings
            "USDC amount out is wrong"
        );

        // Check LP Balances.
        assertEq(vars.lpAfter.dai, vars.lpBefore.dai + amountsOut[vars.daiIdx], "LP Dai Balance is wrong");
        assertEq(vars.lpAfter.weth, vars.lpBefore.weth + amountsOut[vars.wethIdx], "LP Weth Balance is wrong");
        assertEq(vars.lpAfter.usdc, vars.lpBefore.usdc + amountsOut[vars.usdcIdx], "LP Usdc Balance is wrong");
        assertEq(
            vars.lpAfter.childPoolERC4626Bpt,
            vars.lpBefore.childPoolERC4626Bpt,
            "LP ChildPoolA BPT Balance is wrong"
        );
        assertEq(
            vars.lpAfter.parentPoolWithWrapperBpt,
            vars.lpBefore.parentPoolWithWrapperBpt - exactBptIn,
            "LP ParentPool BPT Balance is wrong"
        );

        // Check Vault Balances. Since the buffer has liquidity, the Vault only lost underlying amounts.
        assertEq(vars.vaultAfter.dai, vars.vaultBefore.dai - amountsOut[vars.daiIdx], "Vault Dai Balance is wrong");
        assertEq(vars.vaultAfter.waDAI, vars.vaultBefore.waDAI, "Vault waDai Balance is wrong");
        assertEq(vars.vaultAfter.weth, vars.vaultBefore.weth - amountsOut[vars.wethIdx], "Vault Weth Balance is wrong");
        assertEq(vars.vaultAfter.usdc, vars.vaultBefore.usdc - amountsOut[vars.usdcIdx], "Vault Usdc Balance is wrong");
        assertEq(vars.vaultAfter.waUSDC, vars.vaultBefore.waUSDC, "Vault waUSDC Balance is wrong");

        // Since all Child Pool BPTs were allocated in the parent pool, vault was holding all of them. Since part of
        // them was burned when liquidity was removed, we need to discount this amount from the Vault reserves.
        assertEq(
            vars.vaultAfter.childPoolERC4626Bpt,
            vars.vaultBefore.childPoolERC4626Bpt - burnedChildPoolERC4626Bpts,
            "Vault childPoolERC4626 BPT Balance is wrong"
        );

        // Vault did not hold the parent pool BPTs.
        assertEq(
            vars.vaultAfter.parentPoolWithWrapperBpt,
            vars.vaultBefore.parentPoolWithWrapperBpt,
            "Vault ParentPoolWithWrapper BPT Balance is wrong"
        );

        // Check ChildPoolERC4626
        assertEq(
            vars.childPoolERC4626After.weth,
            vars.childPoolERC4626Before.weth - amountsOut[vars.wethIdx],
            "ChildPoolERC4626 Weth Balance is wrong"
        );
        assertApproxEqAbs(
            vars.childPoolERC4626After.waDAI,
            vars.childPoolERC4626Before.waDAI - waDAI.previewWithdraw(amountsOut[vars.daiIdx]),
            MAX_ROUND_ERROR,
            "ChildPoolERC4626 waDAI Balance is wrong"
        );

        // Check ParentPoolWithWrapper.
        assertApproxEqAbs(
            vars.parentPoolWithWrapperAfter.waUSDC,
            vars.parentPoolWithWrapperBefore.waUSDC - waUSDC.previewWithdraw(amountsOut[vars.usdcIdx]),
            MAX_ROUND_ERROR,
            "ParentPoolWithWrapper waUSDC Balance is wrong"
        );
        assertEq(
            vars.parentPoolWithWrapperAfter.childPoolERC4626Bpt,
            vars.parentPoolWithWrapperBefore.childPoolERC4626Bpt - burnedChildPoolERC4626Bpts,
            "ParentPool ChildPoolERC4626 BPT Balance is wrong"
        );
    }

    function testQueryRemoveLiquidityNestedERC4626Pool__Fuzz(uint256 proportionToRemove) public {
        // Remove between 0.0001% and 50% of each pool liquidity.
        proportionToRemove = bound(proportionToRemove, 1e12, 50e16);

        uint256 totalPoolBPTs = BalancerPoolToken(parentPoolWithWrapper).totalSupply();
        // Since LP is the owner of all BPT supply, and part of the BPTs were burned in the initialization step, using
        // totalSupply is more accurate to remove exactly the proportion that we intend from each pool.
        uint256 exactBptIn = totalPoolBPTs.mulDown(proportionToRemove);

        NestedPoolTestLocals memory vars = _createNestedPoolTestLocals();
        // Override indexes, since wstEth is not used in this test.
        vars.daiIdx = 0;
        vars.usdcIdx = 1;
        vars.wethIdx = 2;

        // During pool initialization, POOL_MINIMUM_TOTAL_SUPPLY amount of BPT is burned to address(0), so that the
        // pool cannot be completely drained. We need to discount this amount of tokens from the total liquidity that
        // we can extract from the child pools.
        uint256 deadTokens = (POOL_MINIMUM_TOTAL_SUPPLY / 4).mulDown(proportionToRemove);

        address[] memory tokensOut = new address[](3);
        tokensOut[vars.daiIdx] = address(dai);
        tokensOut[vars.wethIdx] = address(weth);
        tokensOut[vars.usdcIdx] = address(usdc);

        uint256[] memory expectedAmountsOut = new uint256[](3);
        // Since pools are in their initial state, we can use poolInitAmount as the balance of each token in the pool.
        // Also, we only need to account for deadTokens once, since we calculate the BPT in for the parent pool using
        // totalSupply (so the burned POOL_MINIMUM_TOTAL_SUPPLY amount does not affect the BPT in circulation, and the
        // amounts out are perfectly proportional to the parent pool balance).
        expectedAmountsOut[vars.daiIdx] = waDAI.previewRedeem(
            poolInitAmount.mulDown(proportionToRemove) - deadTokens - MAX_ROUND_ERROR
        );
        expectedAmountsOut[vars.wethIdx] = poolInitAmount.mulDown(proportionToRemove) - deadTokens - MAX_ROUND_ERROR;
        expectedAmountsOut[vars.usdcIdx] = waUSDC.previewRedeem(
            poolInitAmount.mulDown(proportionToRemove) - MAX_ROUND_ERROR
        );

        uint256 snapshotId = vm.snapshot();
        vm.prank(lp, address(0));
        uint256[] memory queryAmountsOut = compositeLiquidityRouter.queryRemoveLiquidityProportionalNestedPool(
            parentPoolWithWrapper,
            exactBptIn,
            tokensOut,address(this),
            bytes("")
        );
        vm.revertTo(snapshotId);

        vm.prank(lp);
        uint256[] memory amountsOut = compositeLiquidityRouter.removeLiquidityProportionalNestedPool(
            parentPoolWithWrapper,
            exactBptIn,
            tokensOut,
            expectedAmountsOut,
            bytes("")
        );

        for (uint256 i = 0; i < amountsOut.length; i++) {
            assertEq(amountsOut[i], queryAmountsOut[i], "AmountsOut and QueryAmountsOut do not match");
        }
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

        vm.expectRevert(InputHelpers.InputLengthMismatch.selector);

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
        expectedTokensOut[1] = address(wsteth);
        expectedTokensOut[2] = address(weth);
        expectedTokensOut[3] = address(usdc);

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
        expectedTokensOut[1] = address(wsteth);
        expectedTokensOut[2] = address(weth);
        expectedTokensOut[3] = address(usdc);

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
        uint256 waDaiIdx;
        uint256 waUsdcIdx;
        TokenBalances lpBefore;
        TokenBalances lpAfter;
        TokenBalances vaultBefore;
        TokenBalances vaultAfter;
        TokenBalances childPoolABefore;
        TokenBalances childPoolAAfter;
        TokenBalances childPoolBBefore;
        TokenBalances childPoolBAfter;
        TokenBalances childPoolERC4626Before;
        TokenBalances childPoolERC4626After;
        TokenBalances parentPoolBefore;
        TokenBalances parentPoolAfter;
        TokenBalances parentPoolWithoutWrapperBefore;
        TokenBalances parentPoolWithoutWrapperAfter;
        TokenBalances parentPoolWithWrapperBefore;
        TokenBalances parentPoolWithWrapperAfter;
    }

    struct TokenBalances {
        uint256 dai;
        uint256 weth;
        uint256 wsteth;
        uint256 usdc;
        uint256 waDAI;
        uint256 waUSDC;
        uint256 childPoolABpt;
        uint256 childPoolBBpt;
        uint256 childPoolERC4626Bpt;
        uint256 parentPoolBpt;
        uint256 parentPoolWithoutWrapperBpt;
        uint256 parentPoolWithWrapperBpt;
        uint256 totalSupply;
    }

    function _createNestedPoolTestLocals() private view returns (NestedPoolTestLocals memory vars) {
        // Create output token indexes, randomly chosen (no sort logic).
        (vars.daiIdx, vars.wethIdx, vars.wstethIdx, vars.usdcIdx) = (0, 1, 2, 3);

        vars.lpBefore = _getBalances(lp);
        vars.vaultBefore = _getBalances(address(vault));
        vars.childPoolABefore = _getPoolBalances(childPoolA);
        vars.childPoolBBefore = _getPoolBalances(childPoolB);
        vars.childPoolERC4626Before = _getPoolBalances(childPoolERC4626);
        vars.parentPoolBefore = _getPoolBalances(parentPool);
        vars.parentPoolWithoutWrapperBefore = _getPoolBalances(parentPoolWithoutWrapper);
        vars.parentPoolWithWrapperBefore = _getPoolBalances(parentPoolWithWrapper);
    }

    function _fillNestedPoolTestLocalsAfter(NestedPoolTestLocals memory vars) private view {
        vars.lpAfter = _getBalances(lp);
        vars.vaultAfter = _getBalances(address(vault));
        vars.childPoolAAfter = _getPoolBalances(childPoolA);
        vars.childPoolBAfter = _getPoolBalances(childPoolB);
        vars.childPoolERC4626After = _getPoolBalances(childPoolERC4626);
        vars.parentPoolAfter = _getPoolBalances(parentPool);
        vars.parentPoolWithoutWrapperAfter = _getPoolBalances(parentPoolWithoutWrapper);
        vars.parentPoolWithWrapperAfter = _getPoolBalances(parentPoolWithWrapper);
    }

    function _getBalances(address entity) private view returns (TokenBalances memory balances) {
        balances.dai = dai.balanceOf(entity);
        balances.weth = weth.balanceOf(entity);
        balances.wsteth = wsteth.balanceOf(entity);
        balances.usdc = usdc.balanceOf(entity);
        balances.waDAI = waDAI.balanceOf(entity);
        balances.waUSDC = waUSDC.balanceOf(entity);
        balances.childPoolABpt = IERC20(childPoolA).balanceOf(entity);
        balances.childPoolBBpt = IERC20(childPoolB).balanceOf(entity);
        balances.childPoolERC4626Bpt = IERC20(childPoolERC4626).balanceOf(entity);
        balances.parentPoolBpt = IERC20(parentPool).balanceOf(entity);
        balances.parentPoolWithoutWrapperBpt = IERC20(parentPoolWithoutWrapper).balanceOf(entity);
        balances.parentPoolWithWrapperBpt = IERC20(parentPoolWithWrapper).balanceOf(entity);
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
            } else if (currentToken == IERC20(address(waDAI))) {
                balances.waDAI = poolBalances[i];
            } else if (currentToken == IERC20(address(waUSDC))) {
                balances.waUSDC = poolBalances[i];
            } else if (currentToken == usdc) {
                balances.usdc = poolBalances[i];
            } else if (currentToken == IERC20(childPoolA)) {
                balances.childPoolABpt = poolBalances[i];
            } else if (currentToken == IERC20(childPoolB)) {
                balances.childPoolBBpt = poolBalances[i];
            } else if (currentToken == IERC20(childPoolERC4626)) {
                balances.childPoolERC4626Bpt = poolBalances[i];
            }
        }

        balances.totalSupply = BalancerPoolToken(pool).totalSupply();
    }
}
