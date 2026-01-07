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

    function testAddProportionalAndSwapExactIn__Fuzz(
        uint256 exactAmount,
        uint256 maxAdjustableAmount,
        bool wethIsEth
    ) public {
        uint256[] memory balancesBefore = vault.getCurrentLiveBalances(pool);
        exactAmount = bound(exactAmount, 1e6, balancesBefore[wethIdx] / 2);
        maxAdjustableAmount = exactAmount * 10;

        // Get expected BPT out for the add liquidity from the standard router
        uint256 snapshot = vm.snapshotState();
        _prankStaticCall();
        uint256 expectedBptAmountOut = router.queryAddLiquidityUnbalanced(
            pool,
            [exactAmount, maxAdjustableAmount].toMemoryArray(),
            alice,
            bytes("")
        );
        vm.revertToState(snapshot);

        // Create add liquidity and swap params
        IUnbalancedAddViaSwapRouter.AddLiquidityAndSwapParams memory params = IUnbalancedAddViaSwapRouter
            .AddLiquidityAndSwapParams({
                exactBptAmountOut: expectedBptAmountOut,
                exactToken: weth,
                exactAmount: exactAmount,
                maxAdjustableAmount: maxAdjustableAmount,
                addLiquidityUserData: bytes(""),
                swapUserData: bytes("")
            });

        // Get query amounts in from addLiquidityViaSwapRouter
        snapshot = vm.snapshotState();
        _prankStaticCall();
        uint256[] memory queryAmountsIn = unbalancedAddViaSwapRouter.queryAddLiquidityUnbalanced(pool, alice, params);
        vm.revertToState(snapshot);

        uint256 ethBalanceBefore = address(alice).balance;
        // Stack too deep
        bool _wethIsEth = wethIsEth;
        vm.prank(alice);
        uint256[] memory amountsIn = unbalancedAddViaSwapRouter.addLiquidityUnbalanced{
            value: _wethIsEth ? exactAmount : 0
        }(pool, MAX_UINT256, _wethIsEth, params);

        // Check ETH balance
        if (_wethIsEth) {
            assertApproxEqAbs(
                address(alice).balance,
                ethBalanceBefore - exactAmount,
                ETH_DELTA,
                "ETH balance mismatch (wethIsEth)"
            );
        } else {
            assertEq(address(alice).balance, ethBalanceBefore, "ETH balance mismatch");
        }

        uint256[] memory _balancesBefore = balancesBefore;
        uint256 _exactAmount = exactAmount;
        uint256 _maxAdjustableAmount = maxAdjustableAmount;
        // Compute expected balances with real balances
        uint256[] memory balancesAfter = vault.getCurrentLiveBalances(pool);
        assertApproxEqRel(
            balancesAfter[wethIdx],
            _balancesBefore[wethIdx] + _exactAmount,
            DELTA_RATIO,
            "WETH balance mismatch"
        );
        assertApproxEqRel(
            balancesAfter[daiIdx],
            _balancesBefore[daiIdx] + _maxAdjustableAmount,
            DELTA_RATIO,
            "DAI balance mismatch"
        );

        // Compare real amounts in with query amounts in
        assertEq(amountsIn, queryAmountsIn, "real and query amounts in mismatch");
    }

    function testAddProportionalAndSwapExactInRevertLimitExceeded() public {
        uint256 exactAmount = 1e6;
        uint256 maxAdjustableAmount = exactAmount * 10;

        // Get expected BPT out for the add liquidity from the standard router
        uint256 snapshot = vm.snapshotState();
        _prankStaticCall();
        uint256 expectedBptAmountOut = router.queryAddLiquidityUnbalanced(
            pool,
            [exactAmount * 10, maxAdjustableAmount * 10].toMemoryArray(),
            alice,
            bytes("")
        );
        vm.revertToState(snapshot);

        // Create add liquidity and swap params
        IUnbalancedAddViaSwapRouter.AddLiquidityAndSwapParams memory params = IUnbalancedAddViaSwapRouter
            .AddLiquidityAndSwapParams({
                exactBptAmountOut: expectedBptAmountOut,
                exactToken: weth,
                exactAmount: exactAmount,
                maxAdjustableAmount: maxAdjustableAmount,
                addLiquidityUserData: bytes(""),
                swapUserData: bytes("")
            });

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IUnbalancedAddViaSwapRouter.AmountInAboveMaxAdjustableAmount.selector,
                108999998,
                maxAdjustableAmount
            )
        );
        unbalancedAddViaSwapRouter.addLiquidityUnbalanced(pool, MAX_UINT256, false, params);
    }

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

    function testTriggerExactInPath() public {
        uint256 totalSupply = IERC20(pool).totalSupply();
        uint256[] memory balances = vault.getCurrentLiveBalances(pool);

        uint256 requestedBpt = totalSupply / 100;
        uint256 exactAmount = balances[wethIdx] / 99;

        // Calculate what proportional amounts would be
        uint256[] memory proportionalAmounts = new uint256[](2);
        proportionalAmounts[0] = (balances[0] * requestedBpt) / totalSupply;
        proportionalAmounts[1] = (balances[1] * requestedBpt) / totalSupply;

        // Set maxAdjustableAmount just below the proportional add amount
        // If we took the EXACT_OUT path, it would add to this and exceed the limit
        // Th EXACT_IN path subtracts from it, so should not revert
        uint256 maxAdjustableAmount = proportionalAmounts[daiIdx] - 1;

        // With these parameters, amountsIn[exactTokenIndex] will be 1000 / 100 = 10;
        // and hookParams.operationParams.exactAmount will be 1000 / 99 = 10.10101.
        // Since 10 < 10.10101..., we take the EXACT_IN path.
        IUnbalancedAddViaSwapRouter.AddLiquidityAndSwapParams memory params = IUnbalancedAddViaSwapRouter
            .AddLiquidityAndSwapParams({
                exactBptAmountOut: requestedBpt,
                exactToken: weth,
                exactAmount: exactAmount,
                maxAdjustableAmount: maxAdjustableAmount,
                addLiquidityUserData: bytes(""),
                swapUserData: bytes("")
            });

        vm.prank(alice);
        uint256[] memory amountsIn = unbalancedAddViaSwapRouter.addLiquidityUnbalanced(
            pool,
            MAX_UINT256,
            false,
            params
        );

        assertEq(amountsIn[wethIdx], exactAmount, "Wrong exact amount in");
        assertLt(
            amountsIn[daiIdx],
            proportionalAmounts[daiIdx],
            "Adjustable token amount should be less than the proportional amount"
        );
        // Kind of redundant, as it would revert otherwise
        assertLe(amountsIn[daiIdx], maxAdjustableAmount, "Adjustable token exceeds the limit");
    }
}
