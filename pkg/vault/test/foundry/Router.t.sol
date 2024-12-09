// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IERC20MultiTokenErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IERC20MultiTokenErrors.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { PackedTokenBalance } from "@balancer-labs/v3-solidity-utils/contracts/helpers/PackedTokenBalance.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { MOCK_ROUTER_VERSION } from "../../contracts/test/RouterMock.sol";
import { RouterCommon } from "../../contracts/RouterCommon.sol";
import { BasePoolMath } from "../../contracts/BasePoolMath.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract RouterTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using FixedPoint for *;

    uint256 internal usdcAmountIn = 1e3 * 1e6; // USDC has 6 decimals
    uint256 internal daiAmountIn = 1e3 * 1e18;
    uint256 internal daiAmountOut = 1e2 * 1e18;
    uint256 internal ethAmountIn = 1e3 ether;
    uint256 internal initBpt = 10e18;
    uint256 internal bptAmountOut = 1e18;

    PoolMock internal wethPool;
    PoolMock internal wethPoolNoInit;

    // Track the indices for the local dai/weth pool.
    uint256 internal daiIdxWethPool;
    uint256 internal wethIdx;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    uint256[] internal wethDaiAmountsIn;
    IERC20[] internal wethDaiTokens;

    function setUp() public virtual override {
        rateProvider = deployRateProviderMock();

        BaseVaultTest.setUp();

        approveForPool(IERC20(wethPool));
    }

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "ERC20 Pool";
        string memory symbol = "ERC20POOL";

        newPool = address(deployPoolMock(IVault(address(vault)), name, symbol));
        vm.label(newPool, "pool");

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[0] = rateProvider;
        rateProviders[1] = rateProvider;
        bool[] memory paysYieldFees = new bool[](2);
        paysYieldFees[0] = true;
        paysYieldFees[1] = true;

        factoryMock.registerTestPool(
            newPool,
            vault.buildTokenConfig(
                [address(dai), address(usdc)].toMemoryArray().asIERC20(),
                rateProviders,
                paysYieldFees
            ),
            poolHooksContract,
            lp
        );
        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        wethPool = deployPoolMock(IVault(address(vault)), "ERC20 weth Pool", "ERC20POOL");
        vm.label(address(wethPool), "wethPool");

        factoryMock.registerTestPool(
            address(wethPool),
            vault.buildTokenConfig([address(dai), address(weth)].toMemoryArray().asIERC20()),
            poolHooksContract,
            lp
        );

        (daiIdxWethPool, wethIdx) = getSortedIndexes(address(dai), address(weth));

        wethDaiTokens = InputHelpers.sortTokens([address(weth), address(dai)].toMemoryArray().asIERC20());

        wethDaiAmountsIn = new uint256[](2);
        wethDaiAmountsIn[wethIdx] = ethAmountIn;
        wethDaiAmountsIn[daiIdxWethPool] = daiAmountIn;

        wethPoolNoInit = deployPoolMock(IVault(address(vault)), "ERC20 weth Pool", "ERC20POOL");
        vm.label(address(wethPoolNoInit), "wethPoolNoInit");

        factoryMock.registerTestPool(
            address(wethPoolNoInit),
            vault.buildTokenConfig([address(weth), address(dai)].toMemoryArray().asIERC20()),
            poolHooksContract,
            lp
        );

        poolArgs = abi.encode(vault, name, symbol);
    }

    function initPool() internal override {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);

        vm.prank(lp);
        router.initialize(address(pool), tokens, [poolInitAmount, poolInitAmount].toMemoryArray(), 0, false, bytes(""));

        vm.prank(lp);
        bool wethIsEth = true;
        router.initialize{ value: ethAmountIn }(
            address(wethPool),
            wethDaiTokens,
            wethDaiAmountsIn,
            initBpt,
            wethIsEth,
            bytes("")
        );
    }

    function testInitBalanceOverflow() public {
        address newPool = address(deployPoolMock(IVault(address(vault)), "Big Pool", "BIGPOOL"));
        vm.label(address(newPool), "big pool");

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);

        factoryMock.registerTestPool(newPool, vault.buildTokenConfig(tokens), address(0), lp);

        vm.expectRevert(PackedTokenBalance.BalanceOverflow.selector);
        vm.prank(lp);
        router.initialize(
            address(newPool),
            tokens,
            [type(uint168).max, poolInitAmount].toMemoryArray(),
            0,
            false,
            bytes("")
        );
    }

    function testQuerySwap() public {
        vm.prank(bob);
        vm.expectRevert(EVMCallModeHelpers.NotStaticCall.selector);
        router.querySwapSingleTokenExactIn(pool, usdc, dai, usdcAmountIn, address(this), bytes(""));
    }

    function testDisableQueries() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);

        vault.disableQuery();

        // Authorize alice.
        bytes32 disableQueryRole = vault.getActionId(IVaultAdmin.disableQuery.selector);

        authorizer.grantRole(disableQueryRole, alice);

        vm.expectEmit();
        emit IVaultEvents.VaultQueriesDisabled();

        vm.prank(alice);
        vault.disableQuery();

        vm.expectRevert(IVaultErrors.QueriesDisabled.selector);

        _prankStaticCall();
        router.querySwapSingleTokenExactIn(pool, usdc, dai, usdcAmountIn, address(this), bytes(""));
    }

    function testInitializeBelowMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20MultiTokenErrors.PoolTotalSupplyTooLow.selector, 0));
        router.initialize(
            address(wethPoolNoInit),
            wethDaiTokens,
            [uint256(0), uint256(0)].toMemoryArray(),
            uint256(0),
            false,
            bytes("")
        );
    }

    function testInitializeWETHNoBalance() public {
        require(weth.balanceOf(broke) == 0, "Precondition: WETH balance non-zero");

        bool wethIsEth = false;

        // Revert when sending ETH while wethIsEth is false (caller holds no weth).
        vm.expectRevert("TRANSFER_FROM_FAILED");
        vm.prank(broke);
        router.initialize(address(wethPoolNoInit), wethDaiTokens, wethDaiAmountsIn, initBpt, wethIsEth, bytes(""));
    }

    function testInitializeWETH() public {
        checkAddLiquidityPreConditions();

        vm.prank(alice);
        bptAmountOut = router.initialize(
            address(wethPoolNoInit),
            wethDaiTokens,
            wethDaiAmountsIn,
            initBpt,
            false,
            bytes("")
        );

        // Weth was deposited, pool tokens were minted to Alice.
        assertEq(weth.balanceOf(alice), defaultBalance - ethAmountIn, "Wrong WETH balance");
        assertEq(wethPoolNoInit.balanceOf(alice), bptAmountOut, "Wrong WETH pool balance");
        assertGt(bptAmountOut, 0, "bptAmountOut is zero");
    }

    function testInitializeNativeNoBalance() public {
        checkAddLiquidityPreConditions();

        // Caller does not have enough ETH, even if they hold weth.
        vm.expectRevert(RouterCommon.InsufficientEth.selector);
        vm.prank(alice);
        router.initialize(address(wethPoolNoInit), wethDaiTokens, wethDaiAmountsIn, initBpt, true, bytes(""));
    }

    function testInitializeNative() public {
        checkAddLiquidityPreConditions();

        bool wethIsEth = true;
        vm.startPrank(alice);
        bptAmountOut = router.initialize{ value: ethAmountIn }(
            address(wethPoolNoInit),
            wethDaiTokens,
            wethDaiAmountsIn,
            initBpt,
            wethIsEth,
            bytes("")
        );

        // Weth was deposited, pool tokens were minted to Alice.
        assertEq(alice.balance, defaultBalance - ethAmountIn, "Wrong ETH balance");
        assertEq(wethPoolNoInit.balanceOf(alice), bptAmountOut, "Wrong WETH pool balance");
        assertGt(bptAmountOut, 0, "bptAmountOut is zero");
    }

    function testInitializeNativeExcessEth() public {
        checkAddLiquidityPreConditions();

        bool wethIsEth = true;
        vm.prank(alice);
        bptAmountOut = router.initialize{ value: defaultBalance }(
            address(wethPoolNoInit),
            wethDaiTokens,
            wethDaiAmountsIn,
            initBpt,
            wethIsEth,
            bytes("")
        );

        // Weth was deposited, excess ETH was returned, pool tokens were minted to Alice.
        assertEq(alice.balance, defaultBalance - ethAmountIn, "Wrong ETH balance");
        assertEq(wethPoolNoInit.balanceOf(alice), bptAmountOut, "Wrong WETH pool balance");
        assertGt(bptAmountOut, 0, "bptAmountOut is zero");
    }

    function testAddLiquidityWETHNoBalance() public {
        checkAddLiquidityPreConditions();

        // Revert when sending ETH while wethIsEth is false (caller holds no weth).
        vm.expectRevert("TRANSFER_FROM_FAILED");
        vm.prank(broke);
        router.addLiquidityCustom(address(wethPool), wethDaiAmountsIn, bptAmountOut, false, bytes(""));
    }

    function testAddLiquidityWETH() public {
        checkAddLiquidityPreConditions();

        vm.prank(alice);
        router.addLiquidityCustom(address(wethPool), wethDaiAmountsIn, bptAmountOut, false, bytes(""));

        // Weth was deposited, pool tokens were minted to Alice.
        assertEq(defaultBalance - weth.balanceOf(alice), ethAmountIn, "Wrong ETH balance");
        assertEq(wethPool.balanceOf(alice), bptAmountOut, "Wrong WETH pool balance");
    }

    function testAddLiquidityNativeNoBalance() public {
        checkAddLiquidityPreConditions();

        // Caller does not have enough ETH, even if they hold weth.
        vm.expectRevert(RouterCommon.InsufficientEth.selector);
        vm.prank(alice);
        router.addLiquidityCustom(address(wethPool), wethDaiAmountsIn, bptAmountOut, true, bytes(""));
    }

    function testAddLiquidityNative() public {
        checkAddLiquidityPreConditions();

        vm.prank(alice);
        router.addLiquidityCustom{ value: ethAmountIn }(
            address(wethPool),
            wethDaiAmountsIn,
            bptAmountOut,
            true,
            bytes("")
        );

        // Weth was deposited, pool tokens were minted to Alice.
        assertEq(alice.balance, defaultBalance - ethAmountIn, "Wrong ETH balance");
        assertEq(wethPool.balanceOf(alice), bptAmountOut, "Wrong WETH pool balance");
    }

    function testAddLiquidityNativeExcessEth() public {
        checkAddLiquidityPreConditions();

        vm.prank(alice);
        router.addLiquidityCustom{ value: defaultBalance }(
            address(wethPool),
            wethDaiAmountsIn,
            bptAmountOut,
            true,
            bytes("")
        );

        // Weth was deposited, excess was returned, pool tokens were minted to Alice.
        assertEq(alice.balance, defaultBalance - ethAmountIn, "Wrong ETH balance");
        assertEq(wethPool.balanceOf(alice), bptAmountOut, "Wrong WETH pool balance");
    }

    function testRemoveLiquidityWETH() public {
        // Make Alice an LP and remove its liquidity position afterwards.
        vm.startPrank(alice);
        bool wethIsEth = true;
        uint256 exactBptAmount = bptAmountOut;

        router.addLiquidityCustom{ value: ethAmountIn }(
            address(wethPool),
            wethDaiAmountsIn,
            exactBptAmount,
            wethIsEth,
            bytes("")
        );

        checkRemoveLiquidityPreConditions();

        wethIsEth = false;
        router.removeLiquidityCustom(address(wethPool), exactBptAmount, wethDaiAmountsIn, wethIsEth, bytes(""));

        // Liquidity position was removed, Alice gets weth back.
        assertEq(weth.balanceOf(alice), defaultBalance + ethAmountIn, "Wrong WETH balance");
        assertEq(wethPool.balanceOf(alice), 0, "WETH pool balance is > 0");
        assertEq(alice.balance, defaultBalance - ethAmountIn, "Wrong ETH balance");
    }

    function testRemoveLiquidityNative() public {
        // Make Alice an LP and remove its liquidity position afterwards.
        vm.startPrank(alice);
        bool wethIsEth = true;
        uint256 exactBptAmount = bptAmountOut;
        router.addLiquidityCustom{ value: ethAmountIn }(
            address(wethPool),
            wethDaiAmountsIn,
            exactBptAmount,
            wethIsEth,
            bytes("")
        );

        uint256 aliceNativeBalanceBefore = alice.balance;
        checkRemoveLiquidityPreConditions();

        router.removeLiquidityCustom(
            address(wethPool),
            exactBptAmount,
            [uint256(ethAmountIn), uint256(daiAmountIn)].toMemoryArray(),
            wethIsEth,
            bytes("")
        );

        // Liquidity position was removed, Alice gets ETH back.
        assertEq(weth.balanceOf(alice), defaultBalance, "Wrong WETH balance");
        assertEq(wethPool.balanceOf(alice), 0, "WETH pool balance is > 0");
        assertEq(alice.balance, aliceNativeBalanceBefore + ethAmountIn, "Wrong ETH balance");
    }

    function testRemoveLiquidityRecovery() public {
        // Add initial liquidity.
        uint256[] memory amountsIn = [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray();

        // Perfect add liquidity without rounding errors.
        vm.prank(alice);
        (, bptAmountOut, ) = router.addLiquidityCustom(pool, amountsIn, bptAmount, false, bytes(""));

        // Put pool in recovery mode.
        vault.manualEnableRecoveryMode(pool);

        BaseVaultTest.Balances memory beforeBalances = getBalances(alice);

        // Do a recovery withdrawal.
        uint256 bptAmountIn = bptAmountOut / 2;
        vm.prank(alice);
        uint256[] memory amountsOut = router.removeLiquidityRecovery(
            pool,
            bptAmountIn,
            new uint256[](amountsIn.length)
        );
        assertEq(amountsOut.length, 2, "Incorrect amounts out length");
        assertEq(amountsOut[daiIdx], defaultAmount / 2, "Incorrect DAI amount out");
        assertEq(amountsOut[usdcIdx], defaultAmount / 2, "Incorrect USDC amount out");

        BaseVaultTest.Balances memory afterBalances = getBalances(alice);

        _assertBalanceChangeRemoveLiquidityRecovery(beforeBalances, afterBalances, bptAmountIn, amountsOut);

        // Change rates (would normally incur yield) - test that yield fees are *not* charged to raw balances.
        vault.manualSetAggregateYieldFeePercentage(pool, 50e16);
        rateProvider.mockRate(2e18);
        authorizer.grantRole(vault.getActionId(IVaultAdmin.disableRecoveryMode.selector), admin);
        vm.prank(admin);
        vault.disableRecoveryMode(pool);

        afterBalances = getBalances(alice);

        _assertBalanceChangeRemoveLiquidityRecovery(beforeBalances, afterBalances, bptAmountIn, amountsOut);
    }

    function testRemoveLiquidityRecovery__Fuzz(uint256 amountIn1, uint256 amountIn2, uint256 exitPercentage) public {
        amountIn1 = bound(amountIn1, 1e18, defaultBalance); // 1 to max user balance
        amountIn2 = bound(amountIn2, 1e18, defaultBalance); // 1 to max user balance
        exitPercentage = bound(exitPercentage, 0, FixedPoint.ONE); // 0 to 100%

        // Add initial liquidity.
        uint256[] memory amountsIn = [uint256(amountIn1), uint256(amountIn2)].toMemoryArray();

        vm.prank(alice);
        bptAmountOut = router.addLiquidityUnbalanced(pool, amountsIn, 1, false, bytes(""));

        // Put pool in recovery mode.
        vault.manualEnableRecoveryMode(pool);

        BaseVaultTest.Balances memory beforeBalances = getBalances(alice);

        // Do a recovery withdrawal.
        uint256 bptAmountIn = bptAmountOut.mulDown(exitPercentage);
        (, , uint256[] memory poolBalances, ) = vault.getPoolTokenInfo(pool);
        uint256[] memory expectedAmountsOutRaw = BasePoolMath.computeProportionalAmountsOut(
            poolBalances,
            vault.totalSupply(pool),
            bptAmountIn
        );

        vm.prank(alice);
        uint256[] memory amountsOut = router.removeLiquidityRecovery(
            pool,
            bptAmountIn,
            new uint256[](amountsIn.length)
        );
        assertEq(amountsOut.length, 2, "Incorrect amounts out length");
        assertEq(amountsOut[daiIdx], expectedAmountsOutRaw[daiIdx], "Incorrect DAI amount out");
        assertEq(amountsOut[usdcIdx], expectedAmountsOutRaw[usdcIdx], "Incorrect USDC amount out");

        BaseVaultTest.Balances memory afterBalances = getBalances(alice);

        _assertBalanceChangeRemoveLiquidityRecovery(beforeBalances, afterBalances, bptAmountIn, amountsOut);
    }

    function _assertBalanceChangeRemoveLiquidityRecovery(
        BaseVaultTest.Balances memory beforeBalances,
        BaseVaultTest.Balances memory afterBalances,
        uint256 bptAmountIn,
        uint256[] memory amountsOut
    ) internal view {
        assertEq(afterBalances.aliceBpt, beforeBalances.aliceBpt - bptAmountIn, "Alice BPT is wrong");
        assertEq(
            afterBalances.aliceTokens[daiIdx],
            beforeBalances.aliceTokens[daiIdx] + amountsOut[daiIdx],
            "Alice DAI is wrong"
        );
        assertEq(
            afterBalances.aliceTokens[usdcIdx],
            beforeBalances.aliceTokens[usdcIdx] + amountsOut[usdcIdx],
            "Alice USDC is wrong"
        );

        assertEq(afterBalances.poolSupply, beforeBalances.poolSupply - bptAmountIn, "Pool Supply is wrong");
        assertEq(
            afterBalances.poolTokens[daiIdx],
            beforeBalances.poolTokens[daiIdx] - amountsOut[daiIdx],
            "Pool DAI is wrong"
        );
        assertEq(
            afterBalances.poolTokens[usdcIdx],
            beforeBalances.poolTokens[usdcIdx] - amountsOut[usdcIdx],
            "Pool USDC is wrong"
        );

        assertEq(
            afterBalances.vaultTokens[daiIdx],
            beforeBalances.vaultTokens[daiIdx] - amountsOut[daiIdx],
            "Vault DAI is wrong"
        );
        assertEq(
            afterBalances.vaultTokens[usdcIdx],
            beforeBalances.vaultTokens[usdcIdx] - amountsOut[usdcIdx],
            "Vault USDC is wrong"
        );

        assertEq(
            afterBalances.vaultReserves[daiIdx],
            beforeBalances.vaultReserves[daiIdx] - amountsOut[daiIdx],
            "Vault Reserve DAI is wrong"
        );
        assertEq(
            afterBalances.vaultReserves[usdcIdx],
            beforeBalances.vaultReserves[usdcIdx] - amountsOut[usdcIdx],
            "Vault Reserve USDC is wrong"
        );
        assertEq(
            afterBalances.swapFeeAmounts[daiIdx],
            beforeBalances.swapFeeAmounts[daiIdx],
            "Vault DAI Swap Fee amount changed"
        );
        assertEq(
            afterBalances.swapFeeAmounts[usdcIdx],
            beforeBalances.swapFeeAmounts[usdcIdx],
            "Vault USDC Swap Fee amount changed"
        );
        assertEq(
            afterBalances.yieldFeeAmounts[daiIdx],
            beforeBalances.yieldFeeAmounts[daiIdx],
            "Vault DAI Yield Fee amount changed"
        );
        assertEq(
            afterBalances.yieldFeeAmounts[usdcIdx],
            beforeBalances.yieldFeeAmounts[usdcIdx],
            "Vault USDC Yield Fee amount changed"
        );
    }

    function testSwapExactInWETH() public {
        require(weth.balanceOf(alice) == defaultBalance, "Precondition: wrong WETH balance");

        bool wethIsEth = false;

        vm.prank(alice);
        uint256 outputTokenAmount = router.swapSingleTokenExactIn(
            address(wethPool),
            weth,
            dai,
            ethAmountIn,
            0,
            MAX_UINT256,
            wethIsEth,
            bytes("")
        );

        assertEq(weth.balanceOf(alice), defaultBalance - ethAmountIn, "Wrong WETH balance");
        assertEq(dai.balanceOf(alice), defaultBalance + outputTokenAmount, "Wrong DAI balance");
    }

    function testSwapExactOutWETH() public {
        require(weth.balanceOf(alice) == defaultBalance, "Precondition: wrong WETH balance");
        bool wethIsEth = false;

        vm.prank(alice);
        uint256 outputTokenAmount = router.swapSingleTokenExactOut(
            address(wethPool),
            weth,
            dai,
            daiAmountOut,
            MAX_UINT256,
            MAX_UINT256,
            wethIsEth,
            bytes("")
        );

        assertEq(weth.balanceOf(alice), defaultBalance - outputTokenAmount, "Wrong WETH balance");
        assertEq(dai.balanceOf(alice), defaultBalance + daiAmountOut, "Wrong DAI balance");
    }

    function testSwapExactInNative() public {
        require(weth.balanceOf(alice) == defaultBalance, "Precondition: wrong WETH balance");
        require(alice.balance == defaultBalance, "Precondition: wrong ETH balance");

        bool wethIsEth = true;

        vm.prank(alice);
        router.swapSingleTokenExactIn{ value: ethAmountIn }(
            address(wethPool),
            weth,
            dai,
            ethAmountIn,
            0,
            MAX_UINT256,
            wethIsEth,
            bytes("")
        );

        assertEq(weth.balanceOf(alice), defaultBalance, "Wrong WETH balance");
        assertEq(dai.balanceOf(alice), defaultBalance + ethAmountIn, "Wrong DAI balance");
        assertEq(alice.balance, defaultBalance - ethAmountIn, "Wrong ETH balance");
    }

    function testSwapExactOutNative() public {
        require(weth.balanceOf(alice) == defaultBalance, "Precondition: wrong WETH balance");
        require(alice.balance == defaultBalance, "Precondition: wrong ETH balance");

        bool wethIsEth = true;

        vm.prank(alice);
        router.swapSingleTokenExactOut{ value: daiAmountOut }(
            address(wethPool),
            weth,
            dai,
            daiAmountOut,
            MAX_UINT256,
            MAX_UINT256,
            wethIsEth,
            bytes("")
        );

        assertEq(weth.balanceOf(alice), defaultBalance, "Wrong WETH balance");
        assertEq(dai.balanceOf(alice), defaultBalance + daiAmountOut, "Wrong DAI balance");
        assertEq(alice.balance, defaultBalance - daiAmountOut, "Wrong ETH balance");
    }

    function testSwapNativeExcessEth() public {
        require(weth.balanceOf(alice) == defaultBalance, "Precondition: wrong WETH balance");
        require(alice.balance == defaultBalance, "Precondition: wrong ETH balance");

        bool wethIsEth = true;

        vm.startPrank(alice);
        router.swapSingleTokenExactIn{ value: defaultBalance }(
            address(wethPool),
            weth,
            dai,
            ethAmountIn,
            0,
            MAX_UINT256,
            wethIsEth,
            bytes("")
        );

        // Only ethAmountIn is sent to the Router.
        assertEq(weth.balanceOf(alice), defaultBalance, "Wrong WETH balance");
        assertEq(dai.balanceOf(alice), defaultBalance + ethAmountIn, "Wrong DAI balance");
        assertEq(alice.balance, defaultBalance - ethAmountIn, "Wrong ETH balance");
    }

    function testGetSingleInputArray() public {
        (uint256[] memory amountsGiven, uint256 tokenIndex) = router.getSingleInputArrayAndTokenIndex(pool, dai, 1234);
        assertEq(amountsGiven.length, 2);
        assertEq(amountsGiven[daiIdx], 1234);
        assertEq(amountsGiven[usdcIdx], 0);
        assertEq(tokenIndex, daiIdx);

        (amountsGiven, tokenIndex) = router.getSingleInputArrayAndTokenIndex(pool, usdc, 4321);
        assertEq(amountsGiven.length, 2);
        assertEq(amountsGiven[daiIdx], 0);
        assertEq(amountsGiven[usdcIdx], 4321);
        assertEq(tokenIndex, usdcIdx);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.TokenNotRegistered.selector, weth));
        router.getSingleInputArrayAndTokenIndex(pool, weth, daiAmountIn);
    }

    function testRouterVersion() public view {
        assertEq(router.version(), MOCK_ROUTER_VERSION, "Router version mismatch");
    }

    function checkRemoveLiquidityPreConditions() internal view {
        require(weth.balanceOf(alice) == defaultBalance, "Precondition: Wrong WETH balance");
        require(wethPool.balanceOf(alice) == bptAmountOut, "Precondition: Wrong weth pool balance");
    }

    function checkAddLiquidityPreConditions() internal view {
        require(weth.balanceOf(alice) == defaultBalance, "Precondition: Wrong WETH balance");
        require(alice.balance == defaultBalance, "Precondition: Wrong ETH balance");
        require(wethPool.balanceOf(alice) == 0, "Precondition: Wrong weth pool balance");
    }
}
