// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {stdStorage, StdStorage} from "forge-std/Test.sol";              

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";

import {
    TokenConfig,
    PoolRoleAccounts,
    PoolSwapParams,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BasePoolTest } from "@balancer-labs/v3-vault/test/foundry/utils/BasePoolTest.sol";
import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { RouterMock } from "@balancer-labs/v3-vault/contracts/test/RouterMock.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { LBPoolFactory, LBPParams } from "../../contracts/lbp/LBPoolFactory.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";
import { LBPool } from "../../contracts/lbp/LBPool.sol";

contract LBPoolTest is BasePoolTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 constant DEFAULT_SWAP_FEE = 1e16; // 1%
    uint256 constant TOKEN_AMOUNT = 1e3 * 1e18;
    uint256 constant START_TIME_OFFSET = 1 days;
    uint256 constant END_TIME_OFFSET = 7 days;

    string constant factoryVersion = "Factory v1";
    string constant poolVersion = "Pool v1";

    bool internal allowRemovalOnlyAfterWeightChange;
    bool internal restrictSaleOfBootstrapToken;

    uint256[] internal weights;
    uint256[] internal startWeights;
    uint256[] internal endWeights;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        expectedAddLiquidityBptAmountOut = TOKEN_AMOUNT;
        tokenAmountIn = TOKEN_AMOUNT / 4;
        isTestSwapFeeEnabled = false;

        BasePoolTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        poolMinSwapFeePercentage = 0.001e16; // 0.001%
        poolMaxSwapFeePercentage = 10e16;
    }

    function createPoolFactory() internal override returns (address) {
        LBPoolFactory factory = new LBPoolFactory(
            IVault(address(vault)),
            365 days,
            factoryVersion,
            poolVersion,
            address(router)
        );
        vm.label(address(factory), "LBPoolFactory");

        return address(factory);
    }

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        IERC20[] memory sortedTokens = InputHelpers.sortTokens(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );
        for (uint256 i = 0; i < sortedTokens.length; i++) {
            poolTokens.push(sortedTokens[i]);
            tokenAmounts.push(TOKEN_AMOUNT);
        }

        startWeights = [uint256(50e16), uint256(50e16)].toMemoryArray();

        // Allow pools created by `poolFactory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(poolFactory);

        string memory name = "LB Pool";
        string memory symbol = "LB_POOL";

        endWeights = [uint256(30e16), uint256(70e16)].toMemoryArray();

        uint32 startTime = uint32(block.timestamp + START_TIME_OFFSET);
        uint32 endTime = uint32(startTime + END_TIME_OFFSET);

        allowRemovalOnlyAfterWeightChange = false;
        restrictSaleOfBootstrapToken = false;

        LBPParams memory lbpParams = LBPParams({
            startTime: startTime,
            endTime: endTime,
            endWeights: endWeights,
            bootstrapToken: address(dai),
            allowRemovalOnlyAfterWeightChange: allowRemovalOnlyAfterWeightChange,
            restrictSaleOfBootstrapToken: restrictSaleOfBootstrapToken
        });

        newPool = LBPoolFactory(poolFactory).create(
            name,
            symbol,
            vault.buildTokenConfig(sortedTokens),
            startWeights,
            DEFAULT_SWAP_FEE,
            bob,
            ZERO_BYTES32,
            lbpParams
        );
    }

    function createAndInitNewLBPool(
        uint256 startWeightOne,
        uint256 startWeightTwo,
        uint256 endWeightOne,
        uint256 endWeightTwo,
        uint32 startTime,
        uint32 endTime,
        address bootstrapToken,
        bool allowRemovalOnlyAfterWeightChange,
        bool restrictSaleOfBootstrapToken
    ) internal returns (address pool) {
        IERC20[] memory sortedTokens = InputHelpers.sortTokens(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );
        for (uint256 i = 0; i < sortedTokens.length; i++) {
            poolTokens.push(sortedTokens[i]);
            tokenAmounts.push(TOKEN_AMOUNT);
        }

        startWeights = [uint256(startWeightOne), uint256(startWeightTwo)].toMemoryArray();

        // Allow pools created by `poolFactory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(poolFactory);

        string memory name = "LB Pool";
        string memory symbol = "LB_POOL";

        endWeights = [uint256(endWeightOne), uint256(endWeightTwo)].toMemoryArray();

        //uint32 startTime = uint32(block.timestamp + START_TIME_OFFSET);
        //uint32 endTime = uint32(startTime + END_TIME_OFFSET);

        //allowRemovalOnlyAfterWeightChange = false;
        //restrictSaleOfBootstrapToken = false;

        LBPParams memory lbpParams = LBPParams({
            startTime: startTime,
            endTime: endTime,
            endWeights: endWeights,
            bootstrapToken: address(bootstrapToken),
            allowRemovalOnlyAfterWeightChange: allowRemovalOnlyAfterWeightChange,
            restrictSaleOfBootstrapToken: restrictSaleOfBootstrapToken
        });

        address newPool = LBPoolFactory(poolFactory).create(
            name,
            symbol,
            vault.buildTokenConfig(sortedTokens),
            startWeights,
            DEFAULT_SWAP_FEE,
            bob,
            keccak256(abi.encodePacked(block.timestamp)), // generate pseudorandom salt to avoid collision,
            lbpParams
        );

        uint256[] memory initAmounts = [TOKEN_AMOUNT, TOKEN_AMOUNT].toMemoryArray();

        // start & stop prank to ensure sender is the owner (bob)
        vm.startPrank(bob);
        _initPool(
            newPool,
            initAmounts,
            0
        );
        vm.stopPrank();

        return newPool;
    }

    function testGetTrustedRouter() public view {
        assertEq(LBPool(pool).getTrustedRouter(), address(router), "Wrong trusted router");
    }

    function testPoolAddress() public view override {

        IERC20[] memory sortedTokens = InputHelpers.sortTokens(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        ); 

        uint256[] memory startWeights = new uint256[](2);
        startWeights[0] = 50e16;
        startWeights[1] = 50e16;


        string memory name = "LB Pool";
        string memory symbol = "LB_POOL";

        uint256[] memory endweights = new uint256[](2);
        endweights[0] = 30e16;
        endweights[1] = 70e16;

        uint32 startTime = uint32(block.timestamp + START_TIME_OFFSET);
        uint32 endTime = uint32(startTime + END_TIME_OFFSET);


        bool allowRemovalOnlyAfterWeightChange = false;
        bool restrictSaleOfBootstrapToken = false;

        LBPParams memory lbpParams = LBPParams({
            startTime: startTime,
            endTime: endTime,
            endWeights: endWeights,
            bootstrapToken: address(dai),
            allowRemovalOnlyAfterWeightChange: allowRemovalOnlyAfterWeightChange,
            restrictSaleOfBootstrapToken: restrictSaleOfBootstrapToken
        });

        TokenConfig[] memory tokenConfigs = vault.buildTokenConfig(sortedTokens);

        bytes memory poolArgs = abi.encode(
            WeightedPool.NewPoolParams({
                name: name,
                symbol: symbol,
                numTokens: sortedTokens.length,
                normalizedWeights: startWeights,
                version: poolVersion
            }),
            vault,
            bob,
            address(router),
            lbpParams,
            tokenConfigs
        );

        address calculatedPoolAddress = IBasePoolFactory(poolFactory).getDeploymentAddress(poolArgs, ZERO_BYTES32);
        assertEq(pool, calculatedPoolAddress, "Pool address mismatch");
    }

    /* function testPoolPausedState() public view override {
        (bool paused, uint256 pauseWindow, uint256 bufferPeriod, address pauseManager) = vault.getPoolPausedState(pool);
        assertFalse(paused, "Vault should not be paused initially");
        assertApproxEqAbs(pauseWindow, START_TIMESTAMP + 365 days, 1, "Pause window period mismatch");
        assertApproxEqAbs(bufferPeriod, START_TIMESTAMP + 365 days + 30 days, 1, "Pause buffer period mismatch");
        assertEq(pauseManager, bob, "Pause manager should be 0");
    } */

    function testInitialize() public view override {
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        for (uint256 i = 0; i < poolTokens.length; ++i) {
            // Tokens are transferred from bob (lp/owner)
            assertEq(
                defaultAccountBalance() - poolTokens[i].balanceOf(bob),
                tokenAmounts[i],
                string.concat("LP: Wrong balance for ", Strings.toString(i))
            );

            // Tokens are stored in the Vault
            assertEq(
                poolTokens[i].balanceOf(address(vault)),
                tokenAmounts[i],
                string.concat("LP: Vault balance for ", Strings.toString(i))
            );

            // Tokens are deposited to the pool
            assertEq(
                balances[i],
                tokenAmounts[i],
                string.concat("Pool: Wrong token balance for ", Strings.toString(i))
            );
        }

        // should mint correct amount of BPT poolTokens
        // Account for the precision loss
        assertApproxEqAbs(IERC20(pool).balanceOf(bob), bptAmountOut, DELTA, "LP: Wrong bptAmountOut");
        assertApproxEqAbs(bptAmountOut, expectedAddLiquidityBptAmountOut, DELTA, "Wrong bptAmountOut");
    }

    function initPool() internal override {
        vm.startPrank(bob);
        bptAmountOut = _initPool(
            pool,
            tokenAmounts,
            // Account for the precision loss
            expectedAddLiquidityBptAmountOut - DELTA
        );
        vm.stopPrank();
    }

    // overriding b/c bob needs to be the LP and has contributed double the "normal" amount of tokens
    function testAddLiquidity() public override {
        uint256 oldBptAmount = IERC20(pool).balanceOf(bob);
        vm.prank(bob);
        bptAmountOut = router.addLiquidityUnbalanced(pool, tokenAmounts, tokenAmountIn - DELTA, false, bytes(""));

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        for (uint256 i = 0; i < poolTokens.length; ++i) {
            // Tokens are transferred from Bob
            assertEq(
                defaultAccountBalance() - poolTokens[i].balanceOf(bob),
                tokenAmounts[i] * 2, // x2 because bob (as owner) did init join and subsequent join
                string.concat("LP: Wrong token balance for ", Strings.toString(i))
            );

            // Tokens are stored in the Vault
            assertEq(
                poolTokens[i].balanceOf(address(vault)),
                tokenAmounts[i] * 2,
                string.concat("Vault: Wrong token balance for ", Strings.toString(i))
            );

            assertEq(
                balances[i],
                tokenAmounts[i] * 2,
                string.concat("Pool: Wrong token balance for ", Strings.toString(i))
            );
        }

        uint256 newBptAmount = IERC20(pool).balanceOf(bob);

        // should mint correct amount of BPT poolTokens
        assertApproxEqAbs(newBptAmount - oldBptAmount, bptAmountOut, DELTA, "LP: Wrong bptAmountOut");
        assertApproxEqAbs(bptAmountOut, expectedAddLiquidityBptAmountOut, DELTA, "Wrong bptAmountOut");
    }

    // overriding b/c bob has swap fee authority, not governance
    // TODO: why does this test need to change swap fee anyway?
    function testAddLiquidityUnbalanced() public override {
        vm.prank(bob);
        vault.setStaticSwapFeePercentage(pool, 10e16);

        uint256[] memory amountsIn = tokenAmounts;
        amountsIn[0] = amountsIn[0].mulDown(IBasePool(pool).getMaximumInvariantRatio());
        vm.prank(bob);

        router.addLiquidityUnbalanced(pool, amountsIn, 0, false, bytes(""));
    }

    function testRemoveLiquidity() public override {
        // create a fake router
        bytes memory code = address(router).code;
        address fakeRouter = makeAddr("target");
        vm.etch(fakeRouter, code);

        vm.startPrank(bob);
        uint256 oldBptAmount = IERC20(pool).balanceOf(bob);
        router.addLiquidityUnbalanced(pool, tokenAmounts, tokenAmountIn - DELTA, false, bytes(""));
        uint256 newBptAmount = IERC20(pool).balanceOf(bob);

        IERC20(pool).approve(address(vault), MAX_UINT256);

        uint256 bptAmountIn = newBptAmount - oldBptAmount;

        uint256[] memory minAmountsOut = new uint256[](poolTokens.length);
        for (uint256 i = 0; i < poolTokens.length; ++i) {
            minAmountsOut[i] = less(tokenAmounts[i], 1e4);
        }

        vm.expectRevert(LBPool.RouterNotTrusted.selector);
        IRouter(fakeRouter).removeLiquidityProportional(
            pool,
            bptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );

        uint256[] memory amountsOut = router.removeLiquidityProportional(
            pool,
            bptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );

        vm.stopPrank();

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        for (uint256 i = 0; i < poolTokens.length; ++i) {
            // Tokens are transferred to Bob
            assertApproxEqAbs(
                poolTokens[i].balanceOf(bob) + TOKEN_AMOUNT, // add TOKEN_AMOUNT to account for init join
                defaultAccountBalance(),
                DELTA,
                string.concat("LP: Wrong token balance for ", Strings.toString(i))
            );

            // Tokens are stored in the Vault
            assertApproxEqAbs(
                poolTokens[i].balanceOf(address(vault)),
                tokenAmounts[i],
                DELTA,
                string.concat("Vault: Wrong token balance for ", Strings.toString(i))
            );

            // Tokens are deposited to the pool
            assertApproxEqAbs(
                balances[i],
                tokenAmounts[i],
                DELTA,
                string.concat("Pool: Wrong token balance for ", Strings.toString(i))
            );

            // amountsOut are correct
            assertApproxEqAbs(
                amountsOut[i],
                tokenAmounts[i],
                DELTA,
                string.concat("Wrong token amountOut for ", Strings.toString(i))
            );
        }

        // should return to correct amount of BPT poolTokens
        assertEq(IERC20(pool).balanceOf(bob), oldBptAmount, "LP: Wrong BPT balance");
    }

    function testRemoveLiquidityDuringWeightChange() public {
        uint32 startTime = uint32(block.timestamp + START_TIME_OFFSET);
        uint32 endTime = uint32(startTime + END_TIME_OFFSET);

        address myPool = createAndInitNewLBPool(
            50e16,
            50e16,
            30e16,
            70e16,
            startTime,
            endTime,
            address(dai), // bootstrap token
            true, // allow removal only after weight change
            false // restrict sale of bootstrap token
        );

        uint256 bptAmountIn = IERC20(myPool).balanceOf(bob) / 2;

        uint256[] memory minAmountsOut = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            minAmountsOut[i] = 0;
        }

        // scenario 1: Before weight change has started
        // removing liq should not be allowed
        (uint256 returnedStartTime, uint256 returnedEndTime, ) = LBPool(
            address(myPool)
        ).getGradualWeightUpdateParams();
        assertTrue(returnedStartTime > block.timestamp, "Weight change should not have started yet");
        assertTrue(LBPool(myPool).allowRemovalOnlyAfterWeightChange());

        vm.expectRevert(LBPool.RemovingLiquidityNotAllowed.selector);
        router.removeLiquidityProportional(
            myPool,
            bptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );

        // scenario 2: During weight change
        skip(2 days);
        (returnedStartTime, returnedEndTime, ) = LBPool(
            address(myPool)
        ).getGradualWeightUpdateParams();
        assertTrue(returnedStartTime <= block.timestamp && block.timestamp <= returnedEndTime, "Weight change should be ongoing");

        vm.expectRevert(LBPool.RemovingLiquidityNotAllowed.selector);
        router.removeLiquidityProportional(
            myPool,
            bptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );

        // scenario 3: Weight change has ended
        // call should succeed
        vm.prank(bob);
        IERC20(myPool).approve(address(router), MAX_UINT256);

        skip(7 days);
        (returnedStartTime, returnedEndTime, ) = LBPool(
            address(myPool)
        ).getGradualWeightUpdateParams();
        assertTrue(returnedEndTime <= block.timestamp, "Weight change should have finished");

        vm.prank(bob);
        router.removeLiquidityProportional(
            myPool,
            bptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );
    }

    function testSwap() public override {
        if (!isTestSwapFeeEnabled) {
            vault.manuallySetSwapFee(pool, 0);
        }

        IERC20 tokenIn = poolTokens[tokenIndexIn];
        IERC20 tokenOut = poolTokens[tokenIndexOut];

        uint256 bobBeforeBalanceTokenOut = tokenOut.balanceOf(bob);
        uint256 bobBeforeBalanceTokenIn = tokenIn.balanceOf(bob);

        vm.prank(bob);
        // enable swapping for default pool
        skip (1 days);
        uint256 amountCalculated = router.swapSingleTokenExactIn(
            pool,
            tokenIn,
            tokenOut,
            tokenAmountIn,
            less(tokenAmountOut, 1e3),
            MAX_UINT256,
            false,
            bytes("")
        );

        // Tokens are transferred from Bob
        assertEq(tokenOut.balanceOf(bob), bobBeforeBalanceTokenOut + amountCalculated, "LP: Wrong tokenOut balance");
        assertEq(tokenIn.balanceOf(bob), bobBeforeBalanceTokenIn - tokenAmountIn, "LP: Wrong tokenIn balance");

        // Tokens are stored in the Vault
        assertEq(
            tokenOut.balanceOf(address(vault)),
            tokenAmounts[tokenIndexOut] - amountCalculated,
            "Vault: Wrong tokenOut balance"
        );
        assertEq(
            tokenIn.balanceOf(address(vault)),
            tokenAmounts[tokenIndexIn] + tokenAmountIn,
            "Vault: Wrong tokenIn balance"
        );

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(pool);

        assertEq(balances[tokenIndexIn], tokenAmounts[tokenIndexIn] + tokenAmountIn, "Pool: Wrong tokenIn balance");
        assertEq(
            balances[tokenIndexOut],
            tokenAmounts[tokenIndexOut] - amountCalculated,
            "Pool: Wrong tokenOut balance"
        );
    }

    function testOnlyOwnerCanBeLP() public {
        uint256[] memory amounts = [TOKEN_AMOUNT, TOKEN_AMOUNT].toMemoryArray();

        vm.startPrank(bob);
        router.addLiquidityUnbalanced(address(pool), amounts, 0, false, "");
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BeforeAddLiquidityHookFailed.selector));
        router.addLiquidityUnbalanced(address(pool), amounts, 0, false, "");
        vm.stopPrank();
    }


    function testSwapsBasedOnWeightChangeProcess() public {
        // the deployed pool has weight change started scheduled to be in the future. Swaps are only allowed when weight change has started

        // 1 case: Try to swap before weight change has started
        assertFalse(LBPool(pool).getSwapEnabled(), "Swaps should be disabled before weight change has started");

        vm.prank(alice);
        vm.expectRevert(LBPool.SwapsDisabled.selector);
        router.swapSingleTokenExactIn(
            address(pool),
            IERC20(dai),
            IERC20(usdc),
            TOKEN_AMOUNT / 10,
            0,
            block.timestamp + 1 hours,
            false,
            ""
        );

        // 2 case: Try to swap after weight change has started
        skip(1 days);
        (uint256 returnedStartTime, uint256 returnedEndTime, uint256[] memory returnedEndWeights) = LBPool(
            address(pool)
        ).getGradualWeightUpdateParams();

        assertTrue(LBPool(pool).getSwapEnabled(), "Swaps should be enabled during weight change has started");
        assertTrue(returnedStartTime <= block.timestamp && block.timestamp <= returnedEndTime, "Start time should be in the past");

        vm.prank(alice);
        router.swapSingleTokenExactIn(
            address(pool),
            IERC20(dai),
            IERC20(usdc),
            TOKEN_AMOUNT / 10,
            0,
            block.timestamp + 1 hours,
            false,
            ""
        );

        // 3 case: Weight change has ended
        // swapping is still be possible
        skip(8 days);
        assertTrue(LBPool(pool).getSwapEnabled(), "Swaps should be enabled after weight change has ended");
        assertTrue(returnedEndTime <= block.timestamp, "Weight change should have ended");

        vm.prank(alice);
        router.swapSingleTokenExactIn(
            address(pool),
            IERC20(dai),
            IERC20(usdc),
            TOKEN_AMOUNT / 10,
            0,
            block.timestamp + 1 hours,
            false,
            ""
        );
    }

    function testTokenSwapAllowedGivenIn() public {

        uint32 startTime = uint32(block.timestamp + START_TIME_OFFSET);
        uint32 endTime = uint32(startTime + END_TIME_OFFSET);

        address myPool = createAndInitNewLBPool(
            50e16,
            50e16,
            30e16,
            70e16,
            startTime,
            endTime,
            address(dai), // bootstrap token
            false, //allow removal only after weight change
            true // restrict sale of bootstrap token
        );

        // ensure swaps are enabled (weight change has ended already) to pass the first check
        skip(8 days);
        vm.prank(alice);
        vm.expectRevert(LBPool.SwapOfBootstrapToken.selector);
        router.swapSingleTokenExactIn(
            address(myPool),
            IERC20(dai),
            IERC20(usdc),
            TOKEN_AMOUNT / 10,
            0,
            block.timestamp + 1 hours,
            false,
            ""
        );

        vm.prank(alice);
        vm.expectRevert(LBPool.SwapOfBootstrapToken.selector);
        router.swapSingleTokenExactOut(
            address(myPool),
            IERC20(usdc),
            IERC20(dai),
            TOKEN_AMOUNT / 10,
            0,
            block.timestamp + 1 hours,
            false,
            ""
        );

        vm.prank(alice);
        router.swapSingleTokenExactIn(
            address(myPool),
            IERC20(usdc),
            IERC20(dai),
            TOKEN_AMOUNT / 5,
            0,
            block.timestamp + 1 hours,
            false,
            ""
        );
    }

    function testTokenSwapAllowedGivenOut() public {

        uint32 startTime = uint32(block.timestamp + START_TIME_OFFSET);
        uint32 endTime = uint32(startTime + END_TIME_OFFSET);

        address myPool = createAndInitNewLBPool(
            50e16,
            50e16,
            30e16,
            70e16,
            startTime,
            endTime,
            address(dai), // bootstrap token
            false, //allow removal only after weight change
            true // restrict sale of bootstrap token
        );

        // ensure swaps are enabled (weight change has ended already) to pass the first check
        skip(8 days);
        vm.prank(alice);
        vm.expectRevert(LBPool.SwapOfBootstrapToken.selector);
        router.swapSingleTokenExactIn(
            address(myPool),
            IERC20(dai),
            IERC20(usdc),
            TOKEN_AMOUNT / 10,
            0,
            block.timestamp + 1 hours,
            false,
            ""
        );

        vm.prank(alice);
        vm.expectRevert(LBPool.SwapOfBootstrapToken.selector);
        router.swapSingleTokenExactOut(
            address(myPool),
            IERC20(usdc),
            IERC20(dai),
            TOKEN_AMOUNT / 10,
            0,
            block.timestamp + 1 hours,
            false,
            ""
        );

        vm.prank(alice);
        router.swapSingleTokenExactOut(
            address(myPool),
            IERC20(dai),
            IERC20(usdc),
            100e6,
            type(uint256).max,
            block.timestamp + 1 hours,
            false,
            ""
        );
    }

    function testInvalidBootstrapToken() public {

        // prepare pool creation data
        IERC20[] memory sortedTokens = InputHelpers.sortTokens(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );
        for (uint256 i = 0; i < sortedTokens.length; i++) {
            poolTokens.push(sortedTokens[i]);
            tokenAmounts.push(TOKEN_AMOUNT);
        }

        startWeights = [uint256(40e16), uint256(60e16)].toMemoryArray();

        // Allow pools created by `poolFactory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(poolFactory);

        string memory name = "LB Pool";
        string memory symbol = "LB_POOL";

        endWeights = [uint256(20e16), uint256(80e16)].toMemoryArray();

        uint32 startTime = uint32(block.timestamp + START_TIME_OFFSET);
        uint32 endTime = uint32(startTime + END_TIME_OFFSET);

        allowRemovalOnlyAfterWeightChange = false;
        restrictSaleOfBootstrapToken = false;

        LBPParams memory lbpParams = LBPParams({
            startTime: startTime,
            endTime: endTime,
            endWeights: endWeights,
            bootstrapToken: address(weth),
            allowRemovalOnlyAfterWeightChange: allowRemovalOnlyAfterWeightChange,
            restrictSaleOfBootstrapToken: restrictSaleOfBootstrapToken
        });

        TokenConfig[] memory tokenConfigs = vault.buildTokenConfig(sortedTokens);

        // expecting a LBPool.InvalidBootstrapToken.selector but can only
        // catch the Create2FailedDeployment selector
        vm.expectRevert(Create2.Create2FailedDeployment.selector);

        address newPool = LBPoolFactory(poolFactory).create(
            name,
            symbol,
            tokenConfigs,
            startWeights,
            DEFAULT_SWAP_FEE,
            bob,
            keccak256(abi.encodePacked(block.timestamp)), // generate pseudorandom salt to avoid collision,
            lbpParams
        );
    }

    function testRemovalOnlAfterWeightChange() public {
        uint32 startTime = uint32(block.timestamp + START_TIME_OFFSET);
        uint32 endTime = uint32(startTime + END_TIME_OFFSET);

        address myPool = createAndInitNewLBPool(
            50e16,
            50e16,
            30e16,
            70e16,
            startTime,
            endTime,
            address(dai), // bootstrap token
            false, //allow removal only after weight change
            true // restrict sale of bootstrap token
        );


    }


    function testEnsureNoTimeOverflow() public {
        uint32 startTime = uint32(block.timestamp + START_TIME_OFFSET);
        uint32 endTime = uint32(startTime + END_TIME_OFFSET);

        address myPool = createAndInitNewLBPool(
            50e16,
            50e16,
            30e16,
            70e16,
            startTime,
            endTime,
            address(dai), // bootstrap token
            false, //allow removal only after weight change
            true // restrict sale of bootstrap token
        );

        //vm.prank(bob);
        //vm.expectRevert(stdError.arithmeticError);
        //LBPool(address(pool)).updateWeightsGradually(blockDotTimestampTestStart, type(uint32).max + 1, endWeights);
    }

    function testQuerySwapDuringWeightUpdate() public {
        uint32 startTime = uint32(block.timestamp + START_TIME_OFFSET);
        uint32 endTime = uint32(startTime + END_TIME_OFFSET);

        address myPool = createAndInitNewLBPool(
            50e16, // dai
            50e16, // usdc
            30e16, // dai
            70e16, // usdc
            startTime,
            endTime,
            address(dai), // bootstrap token
            false, //allow removal only after weight change
            false // restrict sale of bootstrap token
        );

        // Cache original time to avoid issues from `block.timestamp` during `vm.warp`
        uint256 blockDotTimestampTestStart = block.timestamp;

        uint256 testDuration = 1 days;
        uint256 weightUpdateStep = 1 hours;
        uint256 constantWeightDuration = 6 hours;
        // uint256 startTime = blockDotTimestampTestStart + constantWeightDuration;

        /* uint256[] memory endWeights = new uint256[](2);
        endWeights[0] = 0.01e18; // 1%
        endWeights[1] = 0.99e18; // 99% */

        uint256 amountIn = TOKEN_AMOUNT / 10;
        uint256 constantWeightSteps = constantWeightDuration / weightUpdateStep;
        uint256 weightUpdateSteps = testDuration / weightUpdateStep;

        uint256 prevAmountOut;
        uint256 amountOut;

        // weight change starts 1 day after deployment and lasts 7 days.
        skip(1 days);
        prevAmountOut = _executeAndUndoSwap(amountIn, myPool);
        // loop moves timestamp forward 7 days in total
        for (uint256 i = 1; i < 21; i++) {
            skip(8 hours);
            amountOut = _executeAndUndoSwap(amountIn, myPool);
            assertTrue(amountOut > prevAmountOut, "Amount out should remain constant before weight update");
            prevAmountOut = amountOut;

        }


        // ensure weight change has ended
        skip(1 days);
        (, uint256 returnedEndTime,) = LBPool(
            address(myPool)
        ).getGradualWeightUpdateParams();
        assertTrue(returnedEndTime <= block.timestamp, "Weight change should have ended");

        prevAmountOut = _executeAndUndoSwap(amountIn, myPool);
        for (uint256 i = 1; i <= 5; i++) {
            skip(5 hours);
            amountOut = _executeAndUndoSwap(amountIn, myPool);
            assertEq(amountOut, prevAmountOut, "Amount out should increase during weight update");
            prevAmountOut = amountOut;
        }
    }

    function testGetGradualWeightUpdateParams() public view {
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + 7 days;
        uint256[] memory endWeights = new uint256[](2);
        endWeights[0] = 0.3e18; // 30%
        endWeights[1] = 0.7e18; // 70%


        (uint256 returnedStartTime, uint256 returnedEndTime, uint256[] memory returnedEndWeights) = LBPool(
            address(pool)
        ).getGradualWeightUpdateParams();

        assertEq(returnedStartTime, startTime, "Start time should match");
        assertEq(returnedEndTime, endTime, "End time should match");
        assertEq(returnedEndWeights.length, endWeights.length, "End weights length should match");
        for (uint256 i = 0; i < endWeights.length; i++) {
            assertEq(returnedEndWeights[i], endWeights[i], "End weight should match");
        }
    }

    function testUpdateWeightsGraduallyMinWeightRevert() public {
        // prepare pool creation data
        IERC20[] memory sortedTokens = InputHelpers.sortTokens(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );
        for (uint256 i = 0; i < sortedTokens.length; i++) {
            poolTokens.push(sortedTokens[i]);
            tokenAmounts.push(TOKEN_AMOUNT);
        }

        startWeights = [uint256(40e16), uint256(60e16)].toMemoryArray();

        // Allow pools created by `poolFactory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(poolFactory);

        string memory name = "LB Pool";
        string memory symbol = "LB_POOL";

        endWeights = [uint256(0.0001e18), uint256(0.9999e18)].toMemoryArray();

        uint32 startTime = uint32(block.timestamp + START_TIME_OFFSET);
        uint32 endTime = uint32(startTime + END_TIME_OFFSET);

        allowRemovalOnlyAfterWeightChange = false;
        restrictSaleOfBootstrapToken = false;

        LBPParams memory lbpParams = LBPParams({
            startTime: startTime,
            endTime: endTime,
            endWeights: endWeights,
            bootstrapToken: address(dai),
            allowRemovalOnlyAfterWeightChange: allowRemovalOnlyAfterWeightChange,
            restrictSaleOfBootstrapToken: restrictSaleOfBootstrapToken
        });

        TokenConfig[] memory tokenConfigs = vault.buildTokenConfig(sortedTokens);

        // reverts with WeightedPool.MinWeight.selector but cannot be cought
        // expecting a Create2FailedDeployment.
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        address newPool = LBPoolFactory(poolFactory).create(
            name,
            symbol,
            tokenConfigs,
            startWeights,
            DEFAULT_SWAP_FEE,
            bob,
            keccak256(abi.encodePacked(block.timestamp)), // generate pseudorandom salt to avoid collision,
            lbpParams
        );
    }

    function testUpdateWeightsGraduallyNormalizedWeightInvariantRevert() public {
        // prepare pool creation data
        IERC20[] memory sortedTokens = InputHelpers.sortTokens(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );
        for (uint256 i = 0; i < sortedTokens.length; i++) {
            poolTokens.push(sortedTokens[i]);
            tokenAmounts.push(TOKEN_AMOUNT);
        }

        startWeights = [uint256(40e16), uint256(60e16)].toMemoryArray();

        // Allow pools created by `poolFactory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(poolFactory);

        string memory name = "LB Pool";
        string memory symbol = "LB_POOL";

        endWeights = [uint256(30e16), uint256(60e16)].toMemoryArray();

        uint32 startTime = uint32(block.timestamp + START_TIME_OFFSET);
        uint32 endTime = uint32(startTime + END_TIME_OFFSET);

        allowRemovalOnlyAfterWeightChange = false;
        restrictSaleOfBootstrapToken = false;

        LBPParams memory lbpParams = LBPParams({
            startTime: startTime,
            endTime: endTime,
            endWeights: endWeights,
            bootstrapToken: address(dai),
            allowRemovalOnlyAfterWeightChange: allowRemovalOnlyAfterWeightChange,
            restrictSaleOfBootstrapToken: restrictSaleOfBootstrapToken
        });

        TokenConfig[] memory tokenConfigs = vault.buildTokenConfig(sortedTokens);

        // reverts with WeightedPool.NormalizedWeightInvariant.selector
        // but cannot be cought
        // expecting a Create2FailedDeployment.
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        address newPool = LBPoolFactory(poolFactory).create(
            name,
            symbol,
            tokenConfigs,
            startWeights,
            DEFAULT_SWAP_FEE,
            bob,
            keccak256(abi.encodePacked(block.timestamp)), // generate pseudorandom salt to avoid collision,
            lbpParams
        );
    }

    function testAddLiquidityRouterNotTrusted() public {
        RouterMock mockRouter = new RouterMock(IVault(address(vault)), weth, permit2);

        uint256[] memory amounts = [TOKEN_AMOUNT, TOKEN_AMOUNT].toMemoryArray();

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(LBPool.RouterNotTrusted.selector));
        mockRouter.addLiquidityUnbalanced(address(pool), amounts, 0, false, "");
        vm.stopPrank();
    }

    function testInvalidTokenCount() public {
        IERC20[] memory sortedTokens1 = InputHelpers.sortTokens([address(dai)].toMemoryArray().asIERC20());
        IERC20[] memory sortedTokens3 = InputHelpers.sortTokens(
            [address(dai), address(usdc), address(weth)].toMemoryArray().asIERC20()
        );

        TokenConfig[] memory tokenConfig1 = vault.buildTokenConfig(sortedTokens1);
        TokenConfig[] memory tokenConfig3 = vault.buildTokenConfig(sortedTokens3);

        LBPParams memory lbpParams = LBPParams({
            startTime: uint32(block.timestamp + 100),
            endTime: uint32(block.timestamp + 200),
            endWeights: endWeights,
            bootstrapToken: address(dai),
            allowRemovalOnlyAfterWeightChange: false,
            restrictSaleOfBootstrapToken: false
        });

        // Attempt to create a pool with 1 token
        vm.expectRevert(InputHelpers.InputLengthMismatch.selector);
        LBPoolFactory(poolFactory).create(
            "Invalid Pool 1",
            "IP1",
            tokenConfig1,
            [uint256(1e18)].toMemoryArray(),
            DEFAULT_SWAP_FEE,
            bob,
            ZERO_BYTES32,
            lbpParams
        );

        // Attempt to create a pool with 3 tokens
        vm.expectRevert(InputHelpers.InputLengthMismatch.selector);
        LBPoolFactory(poolFactory).create(
            "Invalid Pool 3",
            "IP3",
            tokenConfig3,
            [uint256(0.3e18), uint256(0.3e18), uint256(0.4e18)].toMemoryArray(),
            DEFAULT_SWAP_FEE,
            bob,
            ZERO_BYTES32,
            lbpParams
        );
    }

    function testMismatchedWeightsAndTokens() public {
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(poolTokens);

        LBPParams memory lbpParams = LBPParams({
            startTime: uint32(block.timestamp + 100),
            endTime: uint32(block.timestamp + 200),
            endWeights: endWeights,
            bootstrapToken: address(dai),
            allowRemovalOnlyAfterWeightChange: false,
            restrictSaleOfBootstrapToken: false
        });

        vm.expectRevert(InputHelpers.InputLengthMismatch.selector);
        LBPoolFactory(poolFactory).create(
            "Mismatched Pool",
            "MP",
            tokenConfig,
            [uint256(1e18)].toMemoryArray(),
            DEFAULT_SWAP_FEE,
            bob,
            ZERO_BYTES32,
            lbpParams
        );
    }

    function testInitializedWithSwapsDisabled() public {
        // swaps are disabled if the weight change has not started yet. The start time for the pool
        // is in the future, therefor swaps should be disabled
        
        assertFalse(LBPool(pool).getSwapEnabled(), "Swaps should be disabled on initialization");

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(LBPool.SwapsDisabled.selector));
        router.swapSingleTokenExactIn(
            address(pool),
            IERC20(dai),
            IERC20(usdc),
            TOKEN_AMOUNT / 10,
            0,
            block.timestamp,
            false,
            ""
        );
        vm.stopPrank();
    }

    function testUpdateWeightsGraduallyMismatchedEndWeightsTooFew() public {
        // prepare pool creation data
        IERC20[] memory sortedTokens = InputHelpers.sortTokens(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );
        for (uint256 i = 0; i < sortedTokens.length; i++) {
            poolTokens.push(sortedTokens[i]);
            tokenAmounts.push(TOKEN_AMOUNT);
        }

        startWeights = [uint256(40e16), uint256(60e16)].toMemoryArray();

        // Allow pools created by `poolFactory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(poolFactory);

        string memory name = "LB Pool";
        string memory symbol = "LB_POOL";

        endWeights = [uint256(60e16)].toMemoryArray();

        uint32 startTime = uint32(block.timestamp + START_TIME_OFFSET);
        uint32 endTime = uint32(startTime + END_TIME_OFFSET);

        allowRemovalOnlyAfterWeightChange = false;
        restrictSaleOfBootstrapToken = false;

        LBPParams memory lbpParams = LBPParams({
            startTime: startTime,
            endTime: endTime,
            endWeights: endWeights,
            bootstrapToken: address(dai),
            allowRemovalOnlyAfterWeightChange: allowRemovalOnlyAfterWeightChange,
            restrictSaleOfBootstrapToken: restrictSaleOfBootstrapToken
        });

        TokenConfig[] memory tokenConfigs = vault.buildTokenConfig(sortedTokens);

        // reverts with InputLengthMismatch()
        // but cannot be cought
        // expecting a Create2FailedDeployment.
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        address newPool = LBPoolFactory(poolFactory).create(
            name,
            symbol,
            tokenConfigs,
            startWeights,
            DEFAULT_SWAP_FEE,
            bob,
            keccak256(abi.encodePacked(block.timestamp)), // generate pseudorandom salt to avoid collision,
            lbpParams
        );
    }

    function testUpdateWeightsGraduallyMismatchedEndWeightsTooMany() public {
        // prepare pool creation data
        IERC20[] memory sortedTokens = InputHelpers.sortTokens(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );
        for (uint256 i = 0; i < sortedTokens.length; i++) {
            poolTokens.push(sortedTokens[i]);
            tokenAmounts.push(TOKEN_AMOUNT);
        }

        startWeights = [uint256(40e16), uint256(60e16)].toMemoryArray();

        // Allow pools created by `poolFactory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(poolFactory);

        string memory name = "LB Pool";
        string memory symbol = "LB_POOL";

        endWeights = [uint256(20e16), uint256(30e16), uint256(50e16)].toMemoryArray();

        uint32 startTime = uint32(block.timestamp + START_TIME_OFFSET);
        uint32 endTime = uint32(startTime + END_TIME_OFFSET);

        allowRemovalOnlyAfterWeightChange = false;
        restrictSaleOfBootstrapToken = false;

        LBPParams memory lbpParams = LBPParams({
            startTime: startTime,
            endTime: endTime,
            endWeights: endWeights,
            bootstrapToken: address(dai),
            allowRemovalOnlyAfterWeightChange: allowRemovalOnlyAfterWeightChange,
            restrictSaleOfBootstrapToken: restrictSaleOfBootstrapToken
        });

        TokenConfig[] memory tokenConfigs = vault.buildTokenConfig(sortedTokens);

        // reverts with InputLengthMismatch()
        // but cannot be cought
        // expecting a Create2FailedDeployment.
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        address newPool = LBPoolFactory(poolFactory).create(
            name,
            symbol,
            tokenConfigs,
            startWeights,
            DEFAULT_SWAP_FEE,
            bob,
            keccak256(abi.encodePacked(block.timestamp)), // generate pseudorandom salt to avoid collision,
            lbpParams
        );
    }

    function testOnSwapInvalidTokenIndex() public {
        vm.prank(address(vault));

        // skip forward to enable swaps
        skip (2 days);
        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 1e18,
            balancesScaled18: new uint256[](3), // add an extra (non-existent) value to give the bad index a balance
            indexIn: 2, // Invalid token index
            indexOut: 0,
            router: address(router),
            userData: ""
        });

        vm.expectRevert(IVaultErrors.InvalidToken.selector);
        LBPool(pool).onSwap(request);
    }

    function _executeAndUndoSwap(uint256 amountIn, address pool) internal returns (uint256) {
        // Create a storage checkpoint
        uint256 snapshot = vm.snapshot();

        try this.executeSwap(amountIn, pool) returns (uint256 amountOut) {
            // Revert to the snapshot to undo the swap
            vm.revertTo(snapshot);
            return amountOut;
        } catch Error(string memory reason) {
            vm.revertTo(snapshot);
            revert(reason);
        } catch {
            vm.revertTo(snapshot);
            revert("Low level error during swap");
        }
    }

    function executeSwap(uint256 amountIn, address pool) external returns (uint256) {
        // Ensure this contract has enough tokens and allowance
        deal(address(dai), address(bob), amountIn);
        vm.prank(bob);
        IERC20(dai).approve(address(router), amountIn);

        // Perform the actual swap
        vm.prank(bob);
        return
            router.swapSingleTokenExactIn(
                address(pool),
                IERC20(dai),
                IERC20(usdc),
                amountIn,
                0, // minAmountOut: Set to 0 or a minimum amount if desired
                block.timestamp, // deadline = now to ensure it won't timeout
                false, // wethIsEth: Set to false assuming DAI and USDC are not ETH
                "" // userData: Empty bytes as no additional data is needed
            );
    }
}
