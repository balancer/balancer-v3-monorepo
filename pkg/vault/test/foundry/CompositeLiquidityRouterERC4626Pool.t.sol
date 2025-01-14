// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { MOCK_CL_ROUTER_VERSION } from "../../contracts/test/CompositeLiquidityRouterMock.sol";
import { VaultContractsDeployer } from "./utils/VaultContractsDeployer.sol";
import { BaseERC4626BufferTest } from "./utils/BaseERC4626BufferTest.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { PoolFactoryMock, BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract CompositeLiquidityRouterERC4626PoolTest is BaseERC4626BufferTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];
    using FixedPoint for *;

    uint256 constant MIN_AMOUNT = 1e12;

    ERC4626TestToken internal waInvalid;

    uint256 internal partialWaDaiIdx;
    uint256 internal partialWethIdx;
    address internal partialErc4626Pool;

    function setUp() public virtual override {
        BaseERC4626BufferTest.setUp();

        // Invalid wrapper, with a zero underlying asset.
        waInvalid = new ERC4626TestToken(IERC20(address(0)), "Invalid Wrapped", "waInvalid", 18);

        // Calculate indexes of the pair waDAI/WETH.
        (partialWaDaiIdx, partialWethIdx) = getSortedIndexes(address(waDAI), address(weth));
        partialErc4626Pool = _initializePartialERC4626Pool();
    }

    modifier checkBuffersWhenStaticCall(address sender) {
        TestBalances memory balancesBefore = _getTestBalances(sender);

        _;

        TestBalances memory balancesAfter = _getTestBalances(sender);

        assertEq(
            balancesBefore.balances.userTokens[balancesBefore.wethIdx],
            balancesAfter.balances.userTokens[balancesBefore.wethIdx],
            "WETH balance should be the same"
        );

        assertEq(
            balancesBefore.balances.userTokens[balancesBefore.daiIdx],
            balancesAfter.balances.userTokens[balancesBefore.daiIdx],
            "DAI balance should be the same"
        );

        assertEq(
            balancesBefore.waWETHBuffer.wrapped,
            balancesAfter.waWETHBuffer.wrapped,
            "waWETH wrapped buffer balance should be the same"
        );
        assertEq(
            balancesBefore.waWETHBuffer.underlying,
            balancesAfter.waWETHBuffer.underlying,
            "waWETH underlying buffer balance should be the same"
        );

        assertEq(
            balancesBefore.waDAIBuffer.wrapped,
            balancesAfter.waDAIBuffer.wrapped,
            "waDAI wrapped buffer balance should be the same"
        );
        assertEq(
            balancesBefore.waDAIBuffer.underlying,
            balancesAfter.waDAIBuffer.underlying,
            "waDAI underlying buffer balance should be the same"
        );
    }

    function testAddLiquidityUnbalancedToERC4626Pool__Fuzz(uint256 rawOperationAmount) public {
        uint256 operationAmount = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        uint256[] memory exactWrappedAmountsIn = new uint256[](2);
        exactWrappedAmountsIn[waDaiIdx] = _vaultPreviewDeposit(waDAI, operationAmount);
        exactWrappedAmountsIn[waWethIdx] = _vaultPreviewDeposit(waWETH, operationAmount);

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256 expectBPTOut = router.queryAddLiquidityUnbalanced(
            pool,
            exactWrappedAmountsIn,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshot);

        TestBalances memory balancesBefore = _getTestBalances(alice);

        vm.prank(alice);
        uint256 bptOut = compositeLiquidityRouter.addLiquidityUnbalancedToERC4626Pool(
            pool,
            new bool[](exactUnderlyingAmountsIn.length),
            exactUnderlyingAmountsIn,
            1,
            false,
            bytes("")
        );

        TestBalances memory balancesAfter = _getTestBalances(alice);

        TestLocals memory vars;
        vars.underlyingDaiAmountDelta = exactUnderlyingAmountsIn[waDaiIdx];
        vars.underlyingWethAmountDelta = exactUnderlyingAmountsIn[waWethIdx];
        vars.wrappedDaiPoolDelta = exactWrappedAmountsIn[waDaiIdx];
        vars.wrappedWethPoolDelta = exactWrappedAmountsIn[waWethIdx];
        vars.isPartialERC4626Pool = false;

        _checkBalancesAfterAddLiquidity(balancesBefore, balancesAfter, vars, false);

        assertEq(bptOut, expectBPTOut, "BPT operationAmount should match expected");
        assertEq(IERC20(pool).balanceOf(alice), bptOut, "Alice: wrong BPT balance");
    }

    function testAddLiquidityUnbalancedToERC4626PoolWithWrappedToken__Fuzz(uint256 rawOperationAmount) public {
        uint256 operationAmount = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        uint256[] memory exactWrappedAmountsIn = new uint256[](2);
        exactWrappedAmountsIn[waDaiIdx] = operationAmount;
        exactWrappedAmountsIn[waWethIdx] = _vaultPreviewDeposit(waWETH, operationAmount);

        bool[] memory useAsStandardToken = new bool[](exactUnderlyingAmountsIn.length);
        useAsStandardToken[waDaiIdx] = true;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256 expectBPTOut = router.queryAddLiquidityUnbalanced(
            pool,
            exactWrappedAmountsIn,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshot);

        TestBalances memory balancesBefore = _getTestBalances(alice);

        vm.prank(alice);
        uint256 bptOut = compositeLiquidityRouter.addLiquidityUnbalancedToERC4626Pool(
            pool,
            useAsStandardToken,
            exactUnderlyingAmountsIn,
            1,
            false,
            bytes("")
        );

        TestBalances memory balancesAfter = _getTestBalances(alice);

        TestLocals memory vars;
        vars.underlyingDaiAmountDelta = 0;
        vars.underlyingWethAmountDelta = exactUnderlyingAmountsIn[waWethIdx];
        vars.wrappedDaiPoolDelta = exactWrappedAmountsIn[waDaiIdx];
        vars.wrappedWethPoolDelta = exactWrappedAmountsIn[waWethIdx];
        vars.isPartialERC4626Pool = false;

        _checkBalancesAfterAddLiquidity(balancesBefore, balancesAfter, vars, true);

        assertEq(bptOut, expectBPTOut, "BPT operationAmount should match expected");
        assertEq(IERC20(pool).balanceOf(alice), bptOut, "Alice: wrong BPT balance");
    }

    function testAddLiquidityUnbalancedToERC4626PoolWithEth__Fuzz(
        uint256 rawOperationAmount,
        bool forceEthLeftover
    ) public {
        uint256 operationAmount = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        uint256[] memory exactWrappedAmountsIn = new uint256[](2);
        exactWrappedAmountsIn[waDaiIdx] = _vaultPreviewDeposit(waDAI, operationAmount);
        exactWrappedAmountsIn[waWethIdx] = _vaultPreviewDeposit(waWETH, operationAmount);

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256 expectBPTOut = router.queryAddLiquidityUnbalanced(
            pool,
            exactWrappedAmountsIn,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshot);

        TestBalances memory balancesBefore = _getTestBalances(alice);

        vm.prank(alice);
        uint256 bptOut = compositeLiquidityRouter.addLiquidityUnbalancedToERC4626Pool{
            value: operationAmount + (forceEthLeftover ? 1e18 : 0)
        }(pool, new bool[](exactUnderlyingAmountsIn.length), exactUnderlyingAmountsIn, 1, true, bytes(""));

        TestBalances memory balancesAfter = _getTestBalances(alice);

        TestLocals memory vars;
        vars.underlyingDaiAmountDelta = exactUnderlyingAmountsIn[waDaiIdx];
        vars.underlyingWethAmountDelta = exactUnderlyingAmountsIn[waWethIdx];
        vars.wrappedDaiPoolDelta = exactWrappedAmountsIn[waDaiIdx];
        vars.wrappedWethPoolDelta = exactWrappedAmountsIn[waWethIdx];
        vars.isPartialERC4626Pool = false;
        vars.wethIsEth = true;

        _checkBalancesAfterAddLiquidity(balancesBefore, balancesAfter, vars, false);

        assertEq(bptOut, expectBPTOut, "BPT operationAmount should match expected");
        assertEq(IERC20(pool).balanceOf(alice), bptOut, "Alice: wrong BPT balance");
    }

    function testAddLiquidityUnbalancedZeroToERC4626Pool() public {
        uint256 operationAmount = bufferInitialAmount / 2;

        uint256[] memory exactUnderlyingAmountsIn = new uint256[](2);
        exactUnderlyingAmountsIn[waDaiIdx] = 0;
        exactUnderlyingAmountsIn[waWethIdx] = operationAmount;

        uint256[] memory exactWrappedAmountsIn = new uint256[](2);
        exactWrappedAmountsIn[waDaiIdx] = 0;
        exactWrappedAmountsIn[waWethIdx] = _vaultPreviewDeposit(waWETH, operationAmount);

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256 expectBPTOut = router.queryAddLiquidityUnbalanced(
            pool,
            exactWrappedAmountsIn,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshot);

        TestBalances memory balancesBefore = _getTestBalances(alice);

        vm.prank(alice);
        uint256 bptOut = compositeLiquidityRouter.addLiquidityUnbalancedToERC4626Pool(
            pool,
            new bool[](exactUnderlyingAmountsIn.length),
            exactUnderlyingAmountsIn,
            1,
            false,
            bytes("")
        );

        TestBalances memory balancesAfter = _getTestBalances(alice);

        TestLocals memory vars;
        vars.underlyingDaiAmountDelta = exactUnderlyingAmountsIn[waDaiIdx];
        vars.underlyingWethAmountDelta = exactUnderlyingAmountsIn[waWethIdx];
        vars.wrappedDaiPoolDelta = exactWrappedAmountsIn[waDaiIdx];
        vars.wrappedWethPoolDelta = exactWrappedAmountsIn[waWethIdx];
        vars.isPartialERC4626Pool = false;

        _checkBalancesAfterAddLiquidity(balancesBefore, balancesAfter, vars, false);

        assertEq(bptOut, expectBPTOut, "BPT operationAmount should match expected");
        assertEq(IERC20(pool).balanceOf(alice), bptOut, "Alice: wrong BPT balance");
    }

    function testAddLiquidityUnbalancedToPartialERC4626Pool__Fuzz(uint256 rawOperationAmount) public {
        uint256 operationAmount = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        uint256[] memory exactWrappedAmountsIn = new uint256[](2);
        exactWrappedAmountsIn[partialWaDaiIdx] = _vaultPreviewDeposit(waDAI, operationAmount);
        exactWrappedAmountsIn[partialWethIdx] = operationAmount;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256 expectBPTOut = router.queryAddLiquidityUnbalanced(
            partialErc4626Pool,
            exactWrappedAmountsIn,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshot);

        TestBalances memory balancesBefore = _getTestBalances(alice);

        bool[] memory useAsStandardToken = new bool[](exactUnderlyingAmountsIn.length);
        useAsStandardToken[partialWethIdx] = true;

        vm.prank(alice);
        uint256 bptOut = compositeLiquidityRouter.addLiquidityUnbalancedToERC4626Pool(
            partialErc4626Pool,
            useAsStandardToken,
            exactUnderlyingAmountsIn,
            0,
            false,
            bytes("")
        );

        TestBalances memory balancesAfter = _getTestBalances(alice);

        TestLocals memory vars;
        vars.underlyingDaiAmountDelta = exactUnderlyingAmountsIn[partialWaDaiIdx];
        vars.underlyingWethAmountDelta = exactUnderlyingAmountsIn[partialWethIdx];
        vars.wrappedDaiPoolDelta = exactWrappedAmountsIn[partialWaDaiIdx];
        vars.isPartialERC4626Pool = true;

        _checkBalancesAfterAddLiquidity(balancesBefore, balancesAfter, vars, false);

        assertEq(bptOut, expectBPTOut, "Wrong BPT out");
        assertEq(IERC20(address(partialErc4626Pool)).balanceOf(alice), bptOut, "Alice: wrong BPT balance");
    }

    function testAddLiquidityUnbalancedToPartialERC4626PoolWithEth__Fuzz(
        uint256 rawOperationAmount,
        bool forceEthLeftover
    ) public {
        uint256 operationAmount = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        uint256[] memory exactWrappedAmountsIn = new uint256[](2);
        exactWrappedAmountsIn[partialWaDaiIdx] = _vaultPreviewDeposit(waDAI, operationAmount);
        exactWrappedAmountsIn[partialWethIdx] = operationAmount;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256 expectBPTOut = router.queryAddLiquidityUnbalanced(
            partialErc4626Pool,
            exactWrappedAmountsIn,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshot);

        TestBalances memory balancesBefore = _getTestBalances(alice);

        bool[] memory useAsStandardToken = new bool[](exactUnderlyingAmountsIn.length);
        useAsStandardToken[partialWethIdx] = true;

        vm.prank(alice);
        uint256 bptOut = compositeLiquidityRouter.addLiquidityUnbalancedToERC4626Pool{
            value: operationAmount + (forceEthLeftover ? 1e18 : 0)
        }(partialErc4626Pool, useAsStandardToken, exactUnderlyingAmountsIn, 0, true, bytes(""));

        TestBalances memory balancesAfter = _getTestBalances(alice);

        TestLocals memory vars;
        vars.underlyingDaiAmountDelta = exactUnderlyingAmountsIn[partialWaDaiIdx];
        vars.underlyingWethAmountDelta = exactUnderlyingAmountsIn[partialWethIdx];
        vars.wrappedDaiPoolDelta = exactWrappedAmountsIn[partialWaDaiIdx];
        vars.isPartialERC4626Pool = true;
        vars.wethIsEth = true;

        _checkBalancesAfterAddLiquidity(balancesBefore, balancesAfter, vars, false);

        assertEq(bptOut, expectBPTOut, "Wrong BPT out");
        assertEq(IERC20(address(partialErc4626Pool)).balanceOf(alice), bptOut, "Alice: wrong BPT balance");
    }

    function testAddLiquidityUnbalancedToERC4626PoolWhenStaticCall() public checkBuffersWhenStaticCall(alice) {
        uint256 operationAmount = bufferInitialAmount / 2;
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        _prankStaticCall();
        compositeLiquidityRouter.queryAddLiquidityUnbalancedToERC4626Pool(
            pool,
            new bool[](exactUnderlyingAmountsIn.length),
            exactUnderlyingAmountsIn,
            address(this),
            bytes("")
        );
    }

    function testQueryAddLiquidityUnbalancedToERC4626Pool() public {
        uint256 operationAmount = bufferInitialAmount / 2;
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        uint256 queryBptAmountOut = compositeLiquidityRouter.queryAddLiquidityUnbalancedToERC4626Pool(
            pool,
            new bool[](exactUnderlyingAmountsIn.length),
            exactUnderlyingAmountsIn,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshotId);

        vm.prank(alice);
        uint256 actualBptAmountOut = compositeLiquidityRouter.addLiquidityUnbalancedToERC4626Pool(
            pool,
            new bool[](exactUnderlyingAmountsIn.length),
            exactUnderlyingAmountsIn,
            1,
            false,
            bytes("")
        );

        assertEq(queryBptAmountOut, actualBptAmountOut, "Query and actual bpt amount out do not match");
    }

    function testQueryAddLiquidityUnbalancedZeroToERC4626Pool() public {
        uint256 operationAmount = bufferInitialAmount / 2;
        uint256[] memory exactUnderlyingAmountsIn = [0, operationAmount].toMemoryArray();

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        uint256 queryBptAmountOut = compositeLiquidityRouter.queryAddLiquidityUnbalancedToERC4626Pool(
            pool,
            new bool[](exactUnderlyingAmountsIn.length),
            exactUnderlyingAmountsIn,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshotId);

        vm.prank(alice);
        uint256 actualBptAmountOut = compositeLiquidityRouter.addLiquidityUnbalancedToERC4626Pool(
            pool,
            new bool[](exactUnderlyingAmountsIn.length),
            exactUnderlyingAmountsIn,
            1,
            false,
            bytes("")
        );

        assertEq(queryBptAmountOut, actualBptAmountOut, "Query and actual bpt amount out do not match");
    }

    function testQueryAddLiquidityUnbalancedToPartialERC4626Pool() public {
        uint256 operationAmount = bufferInitialAmount / 2;
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        bool[] memory useAsStandardToken = new bool[](exactUnderlyingAmountsIn.length);
        useAsStandardToken[partialWethIdx] = true;

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        uint256 queryBptAmountOut = compositeLiquidityRouter.queryAddLiquidityUnbalancedToERC4626Pool(
            partialErc4626Pool,
            useAsStandardToken,
            exactUnderlyingAmountsIn,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshotId);

        vm.prank(alice);
        uint256 actualBptAmountOut = compositeLiquidityRouter.addLiquidityUnbalancedToERC4626Pool(
            partialErc4626Pool,
            useAsStandardToken,
            exactUnderlyingAmountsIn,
            1,
            false,
            bytes("")
        );

        assertEq(queryBptAmountOut, actualBptAmountOut, "Query and actual bpt amount out do not match");
    }

    function testAddLiquidityProportionalToERC4626Pool__Fuzz(uint256 rawOperationAmount) public {
        uint256 operationAmount = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);

        uint256[] memory maxAmountsIn = [operationAmount, operationAmount].toMemoryArray();
        uint256 exactBptAmountOut = operationAmount;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedWrappedAmountsIn = router.queryAddLiquidityProportional(
            pool,
            exactBptAmountOut,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshot);

        TestBalances memory balancesBefore = _getTestBalances(alice);

        vm.prank(alice);
        (, uint256[] memory actualUnderlyingAmountsIn) = compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            new bool[](maxAmountsIn.length),
            maxAmountsIn,
            exactBptAmountOut,
            false,
            bytes("")
        );

        TestBalances memory balancesAfter = _getTestBalances(alice);

        TestLocals memory vars;
        vars.underlyingDaiAmountDelta = actualUnderlyingAmountsIn[waDaiIdx];
        vars.underlyingWethAmountDelta = actualUnderlyingAmountsIn[waWethIdx];
        vars.wrappedDaiPoolDelta = expectedWrappedAmountsIn[waDaiIdx];
        vars.wrappedWethPoolDelta = expectedWrappedAmountsIn[waWethIdx];
        vars.isPartialERC4626Pool = false;

        _checkBalancesAfterAddLiquidity(balancesBefore, balancesAfter, vars, false);

        assertEq(
            actualUnderlyingAmountsIn[waDaiIdx],
            _vaultPreviewMint(waDAI, expectedWrappedAmountsIn[waDaiIdx]),
            "DAI actualAmountsInUnderlying should match expected"
        );
        assertEq(
            actualUnderlyingAmountsIn[waWethIdx],
            _vaultPreviewMint(waWETH, expectedWrappedAmountsIn[waWethIdx]),
            "WETH actualAmountsInUnderlying should match expected"
        );

        assertEq(IERC20(pool).balanceOf(alice), exactBptAmountOut, "Alice: BPT balance should increase");
    }

    function testAddLiquidityProportionalToERC4626PoolWithEth__Fuzz(
        uint256 rawOperationAmount,
        bool forceEthLeftover
    ) public {
        uint256 operationAmount = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);

        uint256[] memory maxAmountsIn = [operationAmount, operationAmount].toMemoryArray();
        uint256 exactBptAmountOut = operationAmount;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedWrappedAmountsIn = router.queryAddLiquidityProportional(
            pool,
            exactBptAmountOut,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshot);

        TestBalances memory balancesBefore = _getTestBalances(alice);

        vm.prank(alice);
        (, uint256[] memory actualUnderlyingAmountsIn) = compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool{
            value: operationAmount + (forceEthLeftover ? 1e18 : 0)
        }(pool, new bool[](maxAmountsIn.length), maxAmountsIn, exactBptAmountOut, true, bytes(""));

        TestBalances memory balancesAfter = _getTestBalances(alice);

        TestLocals memory vars;
        vars.underlyingDaiAmountDelta = actualUnderlyingAmountsIn[waDaiIdx];
        vars.underlyingWethAmountDelta = actualUnderlyingAmountsIn[waWethIdx];
        vars.wrappedDaiPoolDelta = expectedWrappedAmountsIn[waDaiIdx];
        vars.wrappedWethPoolDelta = expectedWrappedAmountsIn[waWethIdx];
        vars.isPartialERC4626Pool = false;
        vars.wethIsEth = true;

        _checkBalancesAfterAddLiquidity(balancesBefore, balancesAfter, vars, false);

        assertEq(
            actualUnderlyingAmountsIn[waDaiIdx],
            _vaultPreviewMint(waDAI, expectedWrappedAmountsIn[waDaiIdx]),
            "DAI actualAmountsInUnderlying should match expected"
        );
        assertEq(
            actualUnderlyingAmountsIn[waWethIdx],
            _vaultPreviewMint(waWETH, expectedWrappedAmountsIn[waWethIdx]),
            "WETH actualAmountsInUnderlying should match expected"
        );

        assertEq(IERC20(pool).balanceOf(alice), exactBptAmountOut, "Alice: BPT balance should increase");
    }

    function testAddLiquidityProportionalToPartialERC4626Pool__Fuzz(uint256 rawOperationAmount) public {
        // Make sure the operation is within the buffer liquidity.
        uint256 operationAmount = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 10);

        uint256[] memory maxAmountsIn = [operationAmount, operationAmount].toMemoryArray();
        uint256 exactBptAmountOut = operationAmount;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedWrappedAmountsIn = router.queryAddLiquidityProportional(
            partialErc4626Pool,
            exactBptAmountOut,
            address(this),
            bytes("")
        );

        uint256[] memory expectedUnderlyingAmountsIn = new uint256[](2);
        expectedUnderlyingAmountsIn[partialWaDaiIdx] = _vaultPreviewMint(
            waDAI,
            expectedWrappedAmountsIn[partialWaDaiIdx]
        );
        expectedUnderlyingAmountsIn[partialWethIdx] = expectedWrappedAmountsIn[partialWethIdx];
        vm.revertTo(snapshot);

        TestBalances memory balancesBefore = _getTestBalances(alice);

        bool[] memory useAsStandardToken = new bool[](maxAmountsIn.length);
        useAsStandardToken[partialWethIdx] = true;

        vm.prank(alice);
        (, uint256[] memory actualUnderlyingAmountsIn) = compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            partialErc4626Pool,
            useAsStandardToken,
            maxAmountsIn,
            exactBptAmountOut,
            false,
            bytes("")
        );

        TestBalances memory balancesAfter = _getTestBalances(alice);

        TestLocals memory vars;
        vars.underlyingDaiAmountDelta = actualUnderlyingAmountsIn[partialWaDaiIdx];
        vars.underlyingWethAmountDelta = actualUnderlyingAmountsIn[partialWethIdx];
        vars.wrappedDaiPoolDelta = expectedWrappedAmountsIn[partialWaDaiIdx];
        vars.isPartialERC4626Pool = true;

        _checkBalancesAfterAddLiquidity(balancesBefore, balancesAfter, vars, false);

        assertEq(
            actualUnderlyingAmountsIn[partialWaDaiIdx],
            _vaultPreviewMint(waDAI, expectedWrappedAmountsIn[partialWaDaiIdx]),
            "DAI actualAmountsInUnderlying should match expected"
        );
        assertEq(
            actualUnderlyingAmountsIn[partialWethIdx],
            expectedWrappedAmountsIn[partialWethIdx],
            "WETH actualAmountsInUnderlying should match expected"
        );

        assertEq(IERC20(address(partialErc4626Pool)).balanceOf(alice), exactBptAmountOut, "Alice: wrong BPT balance");
    }

    function testAddLiquidityProportionalToPartialERC4626PoolWithEth__Fuzz(
        uint256 rawOperationAmount,
        bool forceEthLeftover
    ) public {
        // Make sure the operation is within the buffer liquidity.
        uint256 operationAmount = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 10);

        uint256[] memory maxAmountsIn = [operationAmount, operationAmount].toMemoryArray();
        uint256 exactBptAmountOut = operationAmount;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedWrappedAmountsIn = router.queryAddLiquidityProportional(
            partialErc4626Pool,
            exactBptAmountOut,
            address(this),
            bytes("")
        );

        uint256[] memory expectedUnderlyingAmountsIn = new uint256[](2);
        expectedUnderlyingAmountsIn[partialWaDaiIdx] = _vaultPreviewMint(
            waDAI,
            expectedWrappedAmountsIn[partialWaDaiIdx]
        );
        expectedUnderlyingAmountsIn[partialWethIdx] = expectedWrappedAmountsIn[partialWethIdx];
        vm.revertTo(snapshot);

        TestBalances memory balancesBefore = _getTestBalances(alice);

        bool[] memory useAsStandardToken = new bool[](maxAmountsIn.length);
        useAsStandardToken[partialWethIdx] = true;

        vm.prank(alice);
        (, uint256[] memory actualUnderlyingAmountsIn) = compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool{
            value: operationAmount + (forceEthLeftover ? 1e18 : 0)
        }(partialErc4626Pool, useAsStandardToken, maxAmountsIn, exactBptAmountOut, true, bytes(""));

        TestBalances memory balancesAfter = _getTestBalances(alice);

        TestLocals memory vars;
        vars.underlyingDaiAmountDelta = actualUnderlyingAmountsIn[partialWaDaiIdx];
        vars.underlyingWethAmountDelta = actualUnderlyingAmountsIn[partialWethIdx];
        vars.wrappedDaiPoolDelta = expectedWrappedAmountsIn[partialWaDaiIdx];
        vars.isPartialERC4626Pool = true;
        vars.wethIsEth = true;

        _checkBalancesAfterAddLiquidity(balancesBefore, balancesAfter, vars, false);

        assertEq(
            actualUnderlyingAmountsIn[partialWaDaiIdx],
            _vaultPreviewMint(waDAI, expectedWrappedAmountsIn[partialWaDaiIdx]),
            "DAI actualAmountsInUnderlying should match expected"
        );
        assertEq(
            actualUnderlyingAmountsIn[partialWethIdx],
            expectedWrappedAmountsIn[partialWethIdx],
            "WETH actualAmountsInUnderlying should match expected"
        );

        assertEq(IERC20(address(partialErc4626Pool)).balanceOf(alice), exactBptAmountOut, "Alice: wrong BPT balance");
    }

    function testAddLiquidityProportionalToERC4626PoolWhenStaticCall() public checkBuffersWhenStaticCall(alice) {
        uint256 operationAmount = bufferInitialAmount / 2;

        _prankStaticCall();
        compositeLiquidityRouter.queryAddLiquidityProportionalToERC4626Pool(
            pool,
            new bool[](2),
            operationAmount,
            address(this),
            bytes("")
        );
    }

    function testAddLiquidityProportionalToPartialERC4626PoolAboveLimit() public {
        // Make sure the operation is within the buffer liquidity.
        uint256 operationAmount = bufferInitialAmount;

        uint256 exactBptAmountOut = operationAmount;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedWrappedAmountsIn = router.queryAddLiquidityProportional(
            partialErc4626Pool,
            exactBptAmountOut,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshot);

        // Place the limit for max amounts in right below the expected value.
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[partialWaDaiIdx] = operationAmount;
        maxAmountsIn[partialWethIdx] = expectedWrappedAmountsIn[partialWethIdx] - 1;

        bool[] memory useAsStandardToken = new bool[](maxAmountsIn.length);
        useAsStandardToken[partialWethIdx] = true;

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.AmountInAboveMax.selector,
                weth,
                expectedWrappedAmountsIn[partialWethIdx],
                maxAmountsIn[partialWethIdx]
            )
        );
        vm.prank(alice);
        compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            partialErc4626Pool,
            useAsStandardToken,
            maxAmountsIn,
            exactBptAmountOut,
            false,
            bytes("")
        );
    }

    function testQueryAddLiquidityProportionalToERC4626Pool() public {
        uint256 operationAmount = bufferInitialAmount / 2;
        uint256[] memory maxAmountsIn = [operationAmount, operationAmount].toMemoryArray();
        uint256 exactBptAmountOut = operationAmount;

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        (, uint256[] memory queryUnderlyingAmountsIn) = compositeLiquidityRouter
            .queryAddLiquidityProportionalToERC4626Pool(
                pool,
                new bool[](maxAmountsIn.length),
                exactBptAmountOut,
                address(this),
                bytes("")
            );
        vm.revertTo(snapshotId);

        vm.prank(alice);
        (, uint256[] memory actualUnderlyingAmountsIn) = compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            pool,
            new bool[](maxAmountsIn.length),
            maxAmountsIn,
            exactBptAmountOut,
            false,
            bytes("")
        );

        for (uint256 i = 0; i < queryUnderlyingAmountsIn.length; i++) {
            assertEq(
                actualUnderlyingAmountsIn[i],
                queryUnderlyingAmountsIn[i],
                "Query and actual underlying amounts in do not match"
            );
        }
    }

    function testQueryAddLiquidityProportionalToPartialERC4626Pool() public {
        uint256 operationAmount = bufferInitialAmount / 2;
        uint256[] memory maxAmountsIn = [operationAmount, operationAmount].toMemoryArray();
        uint256 exactBptAmountOut = operationAmount;

        bool[] memory useAsStandardToken = new bool[](maxAmountsIn.length);
        useAsStandardToken[partialWethIdx] = true;

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        (, uint256[] memory queryUnderlyingAmountsIn) = compositeLiquidityRouter
            .queryAddLiquidityProportionalToERC4626Pool(
                partialErc4626Pool,
                useAsStandardToken,
                exactBptAmountOut,
                address(this),
                bytes("")
            );
        vm.revertTo(snapshotId);

        vm.prank(alice);
        (, uint256[] memory actualUnderlyingAmountsIn) = compositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
            partialErc4626Pool,
            useAsStandardToken,
            maxAmountsIn,
            exactBptAmountOut,
            false,
            bytes("")
        );

        assertEq(
            actualUnderlyingAmountsIn[partialWaDaiIdx],
            queryUnderlyingAmountsIn[partialWaDaiIdx],
            "Query and actual DAI amounts in do not match"
        );

        assertEq(
            queryUnderlyingAmountsIn[partialWethIdx],
            actualUnderlyingAmountsIn[partialWethIdx],
            "Query and actual WETH amounts in do not match"
        );
    }

    function testRemoveLiquidityProportionalFromERC4626Pool__Fuzz(uint256 rawOperationAmount) public {
        uint256 exactBptAmountIn = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedWrappedAmountsOut = router.queryRemoveLiquidityProportional(
            pool,
            exactBptAmountIn,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshot);

        uint256 beforeBPTBalance = IERC20(pool).balanceOf(bob);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[waWethIdx] = _vaultPreviewRedeem(waWETH, expectedWrappedAmountsOut[waWethIdx]);
        minAmountsOut[waDaiIdx] = _vaultPreviewRedeem(waDAI, expectedWrappedAmountsOut[waDaiIdx]);

        TestBalances memory balancesBefore = _getTestBalances(bob);

        vm.prank(bob);
        (, uint256[] memory actualUnderlyingAmountsOut) = compositeLiquidityRouter
            .removeLiquidityProportionalFromERC4626Pool(
                pool,
                new bool[](minAmountsOut.length),
                exactBptAmountIn,
                minAmountsOut,
                false,
                bytes("")
            );

        TestBalances memory balancesAfter = _getTestBalances(bob);

        TestLocals memory vars;
        vars.underlyingDaiAmountDelta = actualUnderlyingAmountsOut[waDaiIdx];
        vars.underlyingWethAmountDelta = actualUnderlyingAmountsOut[waWethIdx];
        vars.wrappedDaiPoolDelta = expectedWrappedAmountsOut[waDaiIdx];
        vars.wrappedWethPoolDelta = expectedWrappedAmountsOut[waWethIdx];
        vars.isPartialERC4626Pool = false;

        _checkBalancesAfterRemoveLiquidity(balancesBefore, balancesAfter, vars, false);

        assertEq(
            actualUnderlyingAmountsOut[waDaiIdx],
            _vaultPreviewRedeem(waDAI, expectedWrappedAmountsOut[waDaiIdx]),
            "DAI actualUnderlyingAmountsOut should match expected"
        );
        assertEq(
            actualUnderlyingAmountsOut[waWethIdx],
            _vaultPreviewRedeem(waWETH, expectedWrappedAmountsOut[waWethIdx]),
            "WETH actualUnderlyingAmountsOut should match expected"
        );

        uint256 afterBPTBalance = IERC20(pool).balanceOf(bob);
        assertEq(afterBPTBalance, beforeBPTBalance - exactBptAmountIn, "Bob: wrong BPT balance");
    }

    function testRemoveLiquidityProportionalFromERC4626PoolWithWrappedToken__Fuzz(uint256 rawOperationAmount) public {
        uint256 exactBptAmountIn = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedWrappedAmountsOut = router.queryRemoveLiquidityProportional(
            pool,
            exactBptAmountIn,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshot);

        uint256 beforeBPTBalance = IERC20(pool).balanceOf(bob);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[waWethIdx] = _vaultPreviewRedeem(waWETH, expectedWrappedAmountsOut[waWethIdx]);
        minAmountsOut[waDaiIdx] = expectedWrappedAmountsOut[waDaiIdx];

        bool[] memory useAsStandardToken = new bool[](2);
        useAsStandardToken[waDaiIdx] = true;

        TestBalances memory balancesBefore = _getTestBalances(bob);

        vm.prank(bob);
        (, uint256[] memory actualUnderlyingAmountsOut) = compositeLiquidityRouter
            .removeLiquidityProportionalFromERC4626Pool(
                pool,
                useAsStandardToken,
                exactBptAmountIn,
                minAmountsOut,
                false,
                bytes("")
            );

        TestBalances memory balancesAfter = _getTestBalances(bob);

        TestLocals memory vars;
        vars.underlyingDaiAmountDelta = 0;
        vars.underlyingWethAmountDelta = actualUnderlyingAmountsOut[waWethIdx];
        vars.wrappedDaiPoolDelta = expectedWrappedAmountsOut[waDaiIdx];
        vars.wrappedWethPoolDelta = expectedWrappedAmountsOut[waWethIdx];
        vars.isPartialERC4626Pool = false;

        _checkBalancesAfterRemoveLiquidity(balancesBefore, balancesAfter, vars, true);

        assertEq(
            actualUnderlyingAmountsOut[waDaiIdx],
            expectedWrappedAmountsOut[waDaiIdx],
            "DAI actualUnderlyingAmountsOut should match expected"
        );
        assertEq(
            actualUnderlyingAmountsOut[waWethIdx],
            _vaultPreviewRedeem(waWETH, expectedWrappedAmountsOut[waWethIdx]),
            "WETH actualUnderlyingAmountsOut should match expected"
        );

        uint256 afterBPTBalance = IERC20(pool).balanceOf(bob);
        assertEq(afterBPTBalance, beforeBPTBalance - exactBptAmountIn, "Bob: wrong BPT balance");
    }

    function testRemoveLiquidityProportionalFromERC4626PoolWithEth__Fuzz(uint256 rawOperationAmount) public {
        uint256 exactBptAmountIn = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedWrappedAmountsOut = router.queryRemoveLiquidityProportional(
            pool,
            exactBptAmountIn,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshot);

        uint256 beforeBPTBalance = IERC20(pool).balanceOf(bob);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[waWethIdx] = _vaultPreviewRedeem(waWETH, expectedWrappedAmountsOut[waWethIdx]);
        minAmountsOut[waDaiIdx] = _vaultPreviewRedeem(waDAI, expectedWrappedAmountsOut[waDaiIdx]);

        TestBalances memory balancesBefore = _getTestBalances(bob);

        vm.prank(bob);
        (, uint256[] memory actualUnderlyingAmountsOut) = compositeLiquidityRouter
            .removeLiquidityProportionalFromERC4626Pool(
                pool,
                new bool[](minAmountsOut.length),
                exactBptAmountIn,
                minAmountsOut,
                true,
                bytes("")
            );

        TestBalances memory balancesAfter = _getTestBalances(bob);

        TestLocals memory vars;
        vars.underlyingDaiAmountDelta = actualUnderlyingAmountsOut[waDaiIdx];
        vars.underlyingWethAmountDelta = actualUnderlyingAmountsOut[waWethIdx];
        vars.wrappedDaiPoolDelta = expectedWrappedAmountsOut[waDaiIdx];
        vars.wrappedWethPoolDelta = expectedWrappedAmountsOut[waWethIdx];
        vars.isPartialERC4626Pool = false;
        vars.wethIsEth = true;

        _checkBalancesAfterRemoveLiquidity(balancesBefore, balancesAfter, vars, false);

        assertEq(
            actualUnderlyingAmountsOut[waDaiIdx],
            _vaultPreviewRedeem(waDAI, expectedWrappedAmountsOut[waDaiIdx]),
            "DAI actualUnderlyingAmountsOut should match expected"
        );
        assertEq(
            actualUnderlyingAmountsOut[waWethIdx],
            _vaultPreviewRedeem(waWETH, expectedWrappedAmountsOut[waWethIdx]),
            "WETH actualUnderlyingAmountsOut should match expected"
        );

        uint256 afterBPTBalance = IERC20(pool).balanceOf(bob);
        assertEq(afterBPTBalance, beforeBPTBalance - exactBptAmountIn, "Bob: wrong BPT balance");
    }

    function testRemoveLiquidityProportionalFromPartialERC4626Pool__Fuzz(uint256 rawOperationAmount) public {
        uint256 exactBptAmountIn = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedWrappedAmountsOut = router.queryRemoveLiquidityProportional(
            partialErc4626Pool,
            exactBptAmountIn,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshot);

        uint256 beforeBPTBalance = IERC20(address(partialErc4626Pool)).balanceOf(bob);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[partialWethIdx] = expectedWrappedAmountsOut[partialWethIdx];
        minAmountsOut[partialWaDaiIdx] = _vaultPreviewRedeem(waDAI, expectedWrappedAmountsOut[partialWaDaiIdx]);

        TestBalances memory balancesBefore = _getTestBalances(bob);

        bool[] memory useAsStandardToken = new bool[](minAmountsOut.length);
        useAsStandardToken[partialWethIdx] = true;

        vm.prank(bob);
        (, uint256[] memory actualUnderlyingAmountsOut) = compositeLiquidityRouter
            .removeLiquidityProportionalFromERC4626Pool(
                partialErc4626Pool,
                useAsStandardToken,
                exactBptAmountIn,
                minAmountsOut,
                false,
                bytes("")
            );

        TestBalances memory balancesAfter = _getTestBalances(bob);

        TestLocals memory vars;
        vars.underlyingDaiAmountDelta = actualUnderlyingAmountsOut[partialWaDaiIdx];
        vars.underlyingWethAmountDelta = actualUnderlyingAmountsOut[partialWethIdx];
        vars.wrappedDaiPoolDelta = expectedWrappedAmountsOut[partialWaDaiIdx];
        vars.isPartialERC4626Pool = true;

        _checkBalancesAfterRemoveLiquidity(balancesBefore, balancesAfter, vars, false);

        assertEq(
            actualUnderlyingAmountsOut[partialWaDaiIdx],
            _vaultPreviewRedeem(waDAI, expectedWrappedAmountsOut[partialWaDaiIdx]),
            "DAI actualUnderlyingAmountsOut should match expected"
        );

        assertEq(
            actualUnderlyingAmountsOut[partialWethIdx],
            expectedWrappedAmountsOut[partialWethIdx],
            "WETH actualUnderlyingAmountsOut should match expected"
        );

        uint256 afterBPTBalance = IERC20(address(partialErc4626Pool)).balanceOf(bob);
        assertEq(afterBPTBalance, beforeBPTBalance - exactBptAmountIn, "Bob: wrong BPT balance");
    }

    function testRemoveLiquidityProportionalFromPartialERC4626PoolWithEth__Fuzz(uint256 rawOperationAmount) public {
        uint256 exactBptAmountIn = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedWrappedAmountsOut = router.queryRemoveLiquidityProportional(
            partialErc4626Pool,
            exactBptAmountIn,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshot);

        uint256 beforeBPTBalance = IERC20(address(partialErc4626Pool)).balanceOf(bob);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[partialWethIdx] = expectedWrappedAmountsOut[partialWethIdx];
        minAmountsOut[partialWaDaiIdx] = _vaultPreviewRedeem(waDAI, expectedWrappedAmountsOut[partialWaDaiIdx]);

        TestBalances memory balancesBefore = _getTestBalances(bob);

        bool[] memory useAsStandardToken = new bool[](minAmountsOut.length);
        useAsStandardToken[partialWethIdx] = true;

        vm.prank(bob);
        (, uint256[] memory actualUnderlyingAmountsOut) = compositeLiquidityRouter
            .removeLiquidityProportionalFromERC4626Pool(
                partialErc4626Pool,
                useAsStandardToken,
                exactBptAmountIn,
                minAmountsOut,
                true,
                bytes("")
            );

        TestBalances memory balancesAfter = _getTestBalances(bob);

        TestLocals memory vars;
        vars.underlyingDaiAmountDelta = actualUnderlyingAmountsOut[partialWaDaiIdx];
        vars.underlyingWethAmountDelta = actualUnderlyingAmountsOut[partialWethIdx];
        vars.wrappedDaiPoolDelta = expectedWrappedAmountsOut[partialWaDaiIdx];
        vars.isPartialERC4626Pool = true;
        vars.wethIsEth = true;

        _checkBalancesAfterRemoveLiquidity(balancesBefore, balancesAfter, vars, false);

        assertEq(
            actualUnderlyingAmountsOut[partialWaDaiIdx],
            _vaultPreviewRedeem(waDAI, expectedWrappedAmountsOut[partialWaDaiIdx]),
            "DAI actualUnderlyingAmountsOut should match expected"
        );

        assertEq(
            actualUnderlyingAmountsOut[partialWethIdx],
            expectedWrappedAmountsOut[partialWethIdx],
            "WETH actualUnderlyingAmountsOut should match expected"
        );

        uint256 afterBPTBalance = IERC20(address(partialErc4626Pool)).balanceOf(bob);
        assertEq(afterBPTBalance, beforeBPTBalance - exactBptAmountIn, "Bob: wrong BPT balance");
    }

    function testRemoveLiquidityProportionalFromERC4626PoolWhenStaticCall() public checkBuffersWhenStaticCall(bob) {
        uint256 exactBptAmountIn = bufferInitialAmount / 2;

        _prankStaticCall();
        compositeLiquidityRouter.queryRemoveLiquidityProportionalFromERC4626Pool(
            pool,
            new bool[](2),
            exactBptAmountIn,
            address(this),
            bytes("")
        );
    }

    function testRemoveLiquidityProportionalFromPartialERC4626PoolBelowLimit() public {
        uint256 exactBptAmountIn = bufferInitialAmount / 2;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedWrappedAmountsOut = router.queryRemoveLiquidityProportional(
            partialErc4626Pool,
            exactBptAmountIn,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshot);

        // Place the limit for min amounts out right above the expected value.
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[partialWethIdx] = expectedWrappedAmountsOut[partialWethIdx] + 1;
        minAmountsOut[partialWaDaiIdx] = _vaultPreviewRedeem(waDAI, expectedWrappedAmountsOut[partialWaDaiIdx]);

        bool[] memory useAsStandardToken = new bool[](minAmountsOut.length);
        useAsStandardToken[partialWethIdx] = true;

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.AmountOutBelowMin.selector,
                weth,
                expectedWrappedAmountsOut[partialWethIdx],
                minAmountsOut[partialWethIdx]
            )
        );
        vm.prank(bob);
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
            partialErc4626Pool,
            useAsStandardToken,
            exactBptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );
    }

    function testQueryRemoveLiquidityProportionalFromERC4626Pool() public {
        uint256 exactBptAmountIn = bufferInitialAmount / 2;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedWrappedAmountsOut = router.queryRemoveLiquidityProportional(
            pool,
            exactBptAmountIn,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshot);

        uint256[] memory minUnderlyingAmountsOut = new uint256[](2);
        minUnderlyingAmountsOut[waWethIdx] = _vaultPreviewRedeem(waWETH, expectedWrappedAmountsOut[waWethIdx]);
        minUnderlyingAmountsOut[waDaiIdx] = _vaultPreviewRedeem(waDAI, expectedWrappedAmountsOut[waDaiIdx]);

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        (, uint256[] memory queryUnderlyingAmountsOut) = compositeLiquidityRouter
            .queryRemoveLiquidityProportionalFromERC4626Pool(
                pool,
                new bool[](minUnderlyingAmountsOut.length),
                exactBptAmountIn,
                address(this),
                bytes("")
            );
        vm.revertTo(snapshotId);

        vm.prank(bob);
        (, uint256[] memory actualUnderlyingAmountsOut) = compositeLiquidityRouter
            .removeLiquidityProportionalFromERC4626Pool(
                pool,
                new bool[](minUnderlyingAmountsOut.length),
                exactBptAmountIn,
                minUnderlyingAmountsOut,
                false,
                bytes("")
            );

        for (uint256 i = 0; i < queryUnderlyingAmountsOut.length; i++) {
            assertEq(
                actualUnderlyingAmountsOut[i],
                queryUnderlyingAmountsOut[i],
                "Query and actual underlying amounts out do not match"
            );
        }
    }

    function testQueryRemoveLiquidityProportionalFromPartialERC4626Pool() public {
        uint256 exactBptAmountIn = bufferInitialAmount / 2;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedWrappedAmountsOut = router.queryRemoveLiquidityProportional(
            partialErc4626Pool,
            exactBptAmountIn,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshot);

        uint256[] memory minUnderlyingAmountsOut = new uint256[](2);
        minUnderlyingAmountsOut[partialWethIdx] = expectedWrappedAmountsOut[partialWethIdx];
        minUnderlyingAmountsOut[partialWaDaiIdx] = _vaultPreviewRedeem(
            waDAI,
            expectedWrappedAmountsOut[partialWaDaiIdx]
        );

        bool[] memory useAsStandardToken = new bool[](minUnderlyingAmountsOut.length);
        useAsStandardToken[partialWethIdx] = true;

        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        (, uint256[] memory queryUnderlyingAmountsOut) = compositeLiquidityRouter
            .queryRemoveLiquidityProportionalFromERC4626Pool(
                partialErc4626Pool,
                useAsStandardToken,
                exactBptAmountIn,
                address(this),
                bytes("")
            );
        vm.revertTo(snapshotId);

        vm.prank(bob);
        (, uint256[] memory actualUnderlyingAmountsOut) = compositeLiquidityRouter
            .removeLiquidityProportionalFromERC4626Pool(
                partialErc4626Pool,
                useAsStandardToken,
                exactBptAmountIn,
                minUnderlyingAmountsOut,
                false,
                bytes("")
            );

        assertEq(
            actualUnderlyingAmountsOut[partialWaDaiIdx],
            queryUnderlyingAmountsOut[partialWaDaiIdx],
            "Query and actual DAI amounts out do not match"
        );

        assertEq(
            queryUnderlyingAmountsOut[partialWethIdx],
            actualUnderlyingAmountsOut[partialWethIdx],
            "Query and actual WETH amounts out do not match"
        );
    }

    function testInvalidUnderlyingToken() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.InvalidUnderlyingToken.selector, waInvalid));
        vm.prank(lp);
        bufferRouter.initializeBuffer(waInvalid, bufferInitialAmount, bufferInitialAmount, 0);
    }

    function testCompositeLiquidityRouterVersion() public view {
        assertEq(compositeLiquidityRouter.version(), MOCK_CL_ROUTER_VERSION, "CL BatchRouter version mismatch");
    }

    struct TestLocals {
        uint256 underlyingDaiAmountDelta;
        uint256 underlyingWethAmountDelta;
        uint256 wrappedDaiPoolDelta;
        uint256 wrappedWethPoolDelta;
        bool isPartialERC4626Pool;
        bool wethIsEth;
    }

    /**
     * @notice Checks balances of vault, user, pool and buffers after adding liquidity to an ERC4626 pool.
     * @dev This function is prepared to handle checks for a full yield-bearing pool (all tokens are ERC4626) or a
     * partial yield-bearing pool (waDAI is ERC4626, and WETH is a standard token).
     */
    function _checkBalancesAfterAddLiquidity(
        TestBalances memory balancesBefore,
        TestBalances memory balancesAfter,
        TestLocals memory vars,
        bool useWrappedDai
    ) private {
        address ybPool = vars.isPartialERC4626Pool ? partialErc4626Pool : pool;
        uint256 ybDaiIdx = vars.isPartialERC4626Pool ? partialWaDaiIdx : waDaiIdx;
        uint256 ybWethIdx = vars.isPartialERC4626Pool ? partialWethIdx : waWethIdx;

        (, , uint256[] memory poolBalances, ) = vault.getPoolTokenInfo(ybPool);

        // When adding liquidity, Alice transfers underlying tokens to the Vault.
        if (vars.wethIsEth) {
            assertEq(
                balancesAfter.balances.aliceEth,
                balancesBefore.balances.aliceEth - vars.underlyingWethAmountDelta,
                "Alice: wrong ETH balance"
            );
            assertEq(
                balancesAfter.balances.aliceTokens[balancesAfter.wethIdx],
                balancesBefore.balances.aliceTokens[balancesBefore.wethIdx],
                "Alice: wrong WETH balance"
            );
        } else {
            assertEq(balancesAfter.balances.aliceEth, balancesBefore.balances.aliceEth, "Alice: wrong ETH balance");
            assertEq(
                balancesAfter.balances.aliceTokens[balancesAfter.wethIdx],
                balancesBefore.balances.aliceTokens[balancesBefore.wethIdx] - vars.underlyingWethAmountDelta,
                "Alice: wrong WETH balance"
            );
        }

        if (useWrappedDai == false) {
            assertEq(
                balancesAfter.balances.aliceTokens[balancesAfter.daiIdx],
                balancesBefore.balances.aliceTokens[balancesBefore.daiIdx] - vars.underlyingDaiAmountDelta,
                "Alice: wrong DAI balance"
            );

            // The underlying tokens are wrapped in the buffer, so the buffer gains underlying and loses wrapped tokens.
            assertEq(
                balancesAfter.waDAIBuffer.underlying,
                balancesBefore.waDAIBuffer.underlying + vars.underlyingDaiAmountDelta,
                "Vault: wrong waDAI underlying buffer balance"
            );

            assertEq(
                balancesAfter.waDAIBuffer.wrapped,
                balancesBefore.waDAIBuffer.wrapped - vars.wrappedDaiPoolDelta,
                "Vault: wrong waDAI wrapped buffer balance"
            );
        } else {
            assertEq(
                balancesAfter.balances.aliceTokens[balancesAfter.waDaiIdx],
                balancesBefore.balances.aliceTokens[balancesBefore.waDaiIdx] - vars.wrappedDaiPoolDelta,
                "Alice: wrong DAI balance"
            );

            assertEq(
                balancesAfter.waDAIBuffer.underlying,
                balancesBefore.waDAIBuffer.underlying,
                "Vault: wrong waDAI underlying buffer balance"
            );

            assertEq(
                balancesAfter.waDAIBuffer.wrapped,
                balancesBefore.waDAIBuffer.wrapped,
                "Vault: wrong waDAI wrapped buffer balance"
            );
        }

        // The pool gains the wrapped tokens from the buffer and mints BPT to the user.
        assertApproxEqAbs(
            poolBalances[ybDaiIdx],
            _vaultPreviewDeposit(waDAI, erc4626PoolInitialAmount) + vars.wrappedDaiPoolDelta + 2,
            2,
            "ERC4626 Pool: wrong waDAI balance"
        );

        if (vars.isPartialERC4626Pool == false) {
            // The underlying tokens are wrapped in the buffer, so the buffer gains underlying and loses wrapped tokens.
            assertEq(
                balancesAfter.waWETHBuffer.wrapped,
                balancesBefore.waWETHBuffer.wrapped - vars.wrappedWethPoolDelta,
                "Vault: wrong waWETH wrapped buffer balance"
            );
            assertEq(
                balancesAfter.waWETHBuffer.underlying,
                balancesBefore.waWETHBuffer.underlying + vars.underlyingWethAmountDelta,
                "Vault: wrong waWETH underlying buffer balance"
            );

            // The pool gains the wrapped tokens from the buffer and mints BPT to the user.
            assertApproxEqAbs(
                poolBalances[ybWethIdx],
                _vaultPreviewDeposit(waWETH, erc4626PoolInitialAmount) + vars.wrappedWethPoolDelta + 2,
                2,
                "ERC4626 Pool: wrong waWETH balance"
            );
        } else {
            // If partially yield-bearing pool, the pool gains the underlying WETH directly.
            assertEq(
                poolBalances[ybWethIdx],
                erc4626PoolInitialAmount + vars.underlyingWethAmountDelta,
                "ERC4626 Pool: wrong WETH balance"
            );
        }

        assertEq(address(compositeLiquidityRouter).balance, 0, "Router has eth balance");
    }

    /**
     * @notice Checks balances of vault, user, pool and buffers after removing liquidity to an ERC4626 pool.
     * @dev This function is prepared to handle checks for a full yield-bearing pool (all tokens are ERC4626) or a
     * partial yield-bearing pool (waDAI is ERC4626, and WETH is a standard token).
     */
    function _checkBalancesAfterRemoveLiquidity(
        TestBalances memory balancesBefore,
        TestBalances memory balancesAfter,
        TestLocals memory vars,
        bool useWrappedDai
    ) private {
        address ybPool = vars.isPartialERC4626Pool ? partialErc4626Pool : pool;
        uint256 ybDaiIdx = vars.isPartialERC4626Pool ? partialWaDaiIdx : waDaiIdx;
        uint256 ybWethIdx = vars.isPartialERC4626Pool ? partialWethIdx : waWethIdx;

        // The yield-bearing pool holds yield-bearing tokens, so in a remove liquidity event we remove yield-bearing
        // tokens from the pool and burn BPT.
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(ybPool);
        assertApproxEqAbs(
            balances[ybDaiIdx],
            _vaultPreviewDeposit(waDAI, erc4626PoolInitialAmount) - vars.wrappedDaiPoolDelta + 2,
            2,
            "ERC4626 Pool: wrong waDAI balance"
        );

        if (useWrappedDai == false) {
            // The wrapped tokens removed from the pool are unwrapped in the buffer, so the user will receive underlying
            // tokens. The buffer loses underlying and gains the wrapped tokens.
            assertEq(
                balancesAfter.waDAIBuffer.wrapped,
                balancesBefore.waDAIBuffer.wrapped + vars.wrappedDaiPoolDelta,
                "Vault: wrong waDAI wrapped buffer balance"
            );

            assertEq(
                balancesAfter.waDAIBuffer.underlying,
                balancesBefore.waDAIBuffer.underlying - vars.underlyingDaiAmountDelta,
                "Vault: wrong waDAI underlying buffer balance"
            );
        } else {
            assertEq(
                balancesAfter.waDAIBuffer.wrapped,
                balancesBefore.waDAIBuffer.wrapped,
                "Vault: wrong waDAI wrapped buffer balance"
            );

            assertEq(
                balancesAfter.waDAIBuffer.underlying,
                balancesBefore.waDAIBuffer.underlying,
                "Vault: wrong waDAI underlying buffer balance"
            );
        }

        if (vars.isPartialERC4626Pool == false) {
            // The yield-bearing pool holds yield-bearing tokens, so in a remove liquidity event we remove
            // yield-bearing tokens from the pool and burn BPT.
            assertEq(
                balances[ybWethIdx],
                _vaultPreviewDeposit(waWETH, erc4626PoolInitialAmount) - vars.wrappedWethPoolDelta,
                "ERC4626 Pool: wrong waWETH balance"
            );

            // The wrapped tokens removed from the pool are unwrapped in the buffer, so the user will receive
            // underlying tokens. The buffer loses underlying and gains the wrapped tokens.
            assertEq(
                balancesAfter.waWETHBuffer.wrapped,
                balancesBefore.waWETHBuffer.wrapped + vars.wrappedWethPoolDelta,
                "Vault: wrong waWETH wrapped buffer balance"
            );
            assertEq(
                balancesAfter.waWETHBuffer.underlying,
                balancesBefore.waWETHBuffer.underlying - vars.underlyingWethAmountDelta,
                "Vault: wrong waWETH underlying buffer balance"
            );
        } else {
            // If pool is partially yield-bearing, no buffer is involved and the pool returns the underlying token
            // directly.
            assertEq(
                balances[ybWethIdx],
                erc4626PoolInitialAmount - vars.underlyingWethAmountDelta,
                "ERC4626 Pool: wrong WETH balance"
            );
        }

        if (useWrappedDai == false) {
            // When removing liquidity, Bob gets underlying tokens.
            assertEq(
                balancesAfter.balances.bobTokens[balancesAfter.daiIdx],
                balancesBefore.balances.bobTokens[balancesBefore.daiIdx] + vars.underlyingDaiAmountDelta,
                "Bob: wrong DAI balance"
            );
        } else {
            // When removing liquidity, Bob gets wrapped tokens.
            assertEq(
                balancesAfter.balances.bobTokens[balancesAfter.waDaiIdx],
                balancesBefore.balances.bobTokens[balancesBefore.waDaiIdx] + vars.wrappedDaiPoolDelta,
                "Bob: wrong DAI balance"
            );
        }

        if (vars.wethIsEth) {
            assertEq(
                balancesAfter.balances.bobEth,
                balancesBefore.balances.bobEth + vars.underlyingWethAmountDelta,
                "Bob: wrong ETH balance"
            );
            assertEq(
                balancesAfter.balances.bobTokens[balancesAfter.wethIdx],
                balancesBefore.balances.bobTokens[balancesBefore.wethIdx],
                "Bob: wrong WETH balance"
            );
        } else {
            assertEq(balancesAfter.balances.bobEth, balancesBefore.balances.bobEth, "Bob: wrong ETH balance");
            assertEq(
                balancesAfter.balances.bobTokens[balancesAfter.wethIdx],
                balancesBefore.balances.bobTokens[balancesBefore.wethIdx] + vars.underlyingWethAmountDelta,
                "Bob: wrong WETH balance"
            );
        }

        assertEq(address(compositeLiquidityRouter).balance, 0, "Router has eth balance");
    }

    function _initializePartialERC4626Pool() private returns (address newPool) {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[partialWaDaiIdx].token = IERC20(waDAI);
        tokenConfig[partialWethIdx].token = IERC20(weth);
        tokenConfig[partialWaDaiIdx].tokenType = TokenType.WITH_RATE;
        tokenConfig[partialWethIdx].tokenType = TokenType.STANDARD;
        tokenConfig[partialWaDaiIdx].rateProvider = IRateProvider(address(waDAI));

        newPool = address(deployPoolMock(IVault(address(vault)), "PARTIAL ERC4626 Pool", "PART-ERC4626P"));

        PoolFactoryMock(poolFactory).registerTestPool(newPool, tokenConfig, poolHooksContract);

        vm.label(newPool, "partial erc4626 pool");

        vm.startPrank(bob);
        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(compositeLiquidityRouter), type(uint160).max, type(uint48).max);

        dai.mint(bob, erc4626PoolInitialAmount);
        dai.approve(address(waDAI), erc4626PoolInitialAmount);
        uint256 waDaiShares = waDAI.deposit(erc4626PoolInitialAmount, bob);

        vm.deal(payable(bob), bob.balance + erc4626PoolInitialAmount);
        weth.deposit{ value: erc4626PoolInitialAmount }();

        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[partialWaDaiIdx] = waDaiShares;
        initAmounts[partialWethIdx] = erc4626PoolInitialAmount;

        _initPool(newPool, initAmounts, 1);

        IERC20(newPool).approve(address(permit2), MAX_UINT256);
        permit2.approve(newPool, address(router), type(uint160).max, type(uint48).max);
        permit2.approve(newPool, address(compositeLiquidityRouter), type(uint160).max, type(uint48).max);

        IERC20(newPool).approve(address(router), type(uint256).max);
        IERC20(newPool).approve(address(compositeLiquidityRouter), type(uint256).max);
        vm.stopPrank();
    }

    struct BufferBalances {
        uint256 underlying;
        uint256 wrapped;
    }

    struct TestBalances {
        BaseVaultTest.Balances balances;
        BufferBalances waWETHBuffer;
        BufferBalances waDAIBuffer;
        uint256 daiIdx;
        uint256 wethIdx;
        uint256 waDaiIdx;
        uint256 waWethIdx;
    }

    function _getTestBalances(address sender) private view returns (TestBalances memory testBalances) {
        IERC20[] memory tokenArray = [address(dai), address(weth), address(waDAI), address(waWETH)]
            .toMemoryArray()
            .asIERC20();
        testBalances.balances = getBalances(sender, tokenArray);

        (uint256 waDAIBufferBalanceUnderlying, uint256 waDAIBufferBalanceWrapped) = vault.getBufferBalance(waDAI);
        testBalances.waDAIBuffer.underlying = waDAIBufferBalanceUnderlying;
        testBalances.waDAIBuffer.wrapped = waDAIBufferBalanceWrapped;

        (uint256 waWETHBufferBalanceUnderlying, uint256 waWETHBufferBalanceWrapped) = vault.getBufferBalance(waWETH);
        testBalances.waWETHBuffer.underlying = waWETHBufferBalanceUnderlying;
        testBalances.waWETHBuffer.wrapped = waWETHBufferBalanceWrapped;

        // The index of each token is defined by the order of tokenArray, defined in this function.
        testBalances.daiIdx = 0;
        testBalances.wethIdx = 1;
        testBalances.waDaiIdx = 2;
        testBalances.waWethIdx = 3;
    }
}
