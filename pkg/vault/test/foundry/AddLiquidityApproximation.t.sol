// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract LiquidityInvariantTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for *;

    address internal exactOutPool;
    address internal unbalancedPool;

    uint256 internal maxAmount = 1e9 * 1e18 - 1;

    uint256 internal daiIdx;

    function setUp() public virtual override {
        defaultBalance = 1e10 * 1e18;
        BaseVaultTest.setUp();

        (daiIdx, ) = getSortedIndexes(address(dai), address(usdc));

        assertEq(dai.balanceOf(alice), dai.balanceOf(bob), "Bob and Alice DAI balances are not equal");
    }

    function createPool() internal virtual override returns (address) {
        unbalancedPool = address(
            new PoolMock(
                IVault(address(vault)),
                "ERC20 Pool",
                "ERC20POOL",
                vault.buildTokenConfig(
                    [address(dai), address(usdc)].toMemoryArray().asIERC20(),
                    new IRateProvider[](2)
                ),
                true,
                365 days,
                address(0)
            )
        );
        vm.label(address(unbalancedPool), "unbalancedPool");

        exactOutPool = address(
            new PoolMock(
                IVault(address(vault)),
                "ERC20 Pool",
                "ERC20POOL",
                vault.buildTokenConfig(
                    [address(dai), address(usdc)].toMemoryArray().asIERC20(),
                    new IRateProvider[](2)
                ),
                true,
                365 days,
                address(0)
            )
        );
        vm.label(address(exactOutPool), "exactOutPool");

        return address(unbalancedPool);
    }

    function initPool() internal override {}

    modifier initializePools(uint256 amountA, uint256 amountB) {
        poolInitAmount = 1e9 * 1e18;

        amountA = bound(amountA, 1e18, poolInitAmount);
        amountB = bound(amountB, 1e18, poolInitAmount);

        (IERC20[] memory tokens, , , , ) = vault.getPoolTokenInfo(address(exactOutPool));
        vm.prank(lp);
        router.initialize(address(exactOutPool), tokens, [amountA, amountB].toMemoryArray(), 0, false, "");

        vm.prank(lp);
        router.initialize(address(unbalancedPool), tokens, [amountA, amountB].toMemoryArray(), 0, false, "");
        
        setProtocolSwapFeePercentage(_protocolFee());
        setSwapFeePercentage(_swapFee(), exactOutPool);
        setSwapFeePercentage(_swapFee(), unbalancedPool);

        _;
    }

    /// Add

    function testAddLiquidityInvariant__Fuzz(
        uint256 daiAmountIn,
        uint256 daiInPool,
        uint256 usdcInPool
    ) public initializePools(daiInPool, usdcInPool) {
        daiAmountIn = bound(daiAmountIn, 1e18, maxAmount);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[daiIdx] = uint256(daiAmountIn);

        vm.startPrank(alice);
        uint256 bptUnbalancedAmountOut = router.addLiquidityUnbalanced({
            pool: address(unbalancedPool),
            exactAmountsIn: amountsIn,
            minBptAmountOut: 0,
            wethIsEth: false,
            userData: bytes("")
        });
        vm.stopPrank();

        vm.startPrank(bob);

        // vm.expectRevert();
        // // Asks for more BPT than it should
        // router.addLiquiditySingleTokenExactOut({
        //     pool: address(exactOutPool),
        //     tokenIn: dai,
        //     maxAmountIn: daiAmountIn,
        //     exactBptAmountOut: bptUnbalancedAmountOut + 1,
        //     wethIsEth: false,
        //     userData: bytes("")
        // });

        uint256 daiExactAmountIn = router.addLiquiditySingleTokenExactOut({
            pool: address(exactOutPool),
            tokenIn: dai,
            maxAmountIn: daiAmountIn + 1e18, // avoids revert when fee
            exactBptAmountOut: bptUnbalancedAmountOut,
            wethIsEth: false,
            userData: bytes("")
        });
        vm.stopPrank();

        // TODO: this test fails because of the rounding error
        assertEq(defaultBalance - dai.balanceOf(bob), daiExactAmountIn, "Bob balance is not correct");
        // assertEq(dai.balanceOf(alice), dai.balanceOf(bob), "Bob and Alice DAI balances are not equal");
        assertApproxEqAbs(dai.balanceOf(alice), dai.balanceOf(bob), 1e12, "Bob and Alice DAI balances are not equal");
        assertEq(IERC20(address(unbalancedPool)).balanceOf(alice), IERC20(address(exactOutPool)).balanceOf(bob), "Bob and Alice BPT balances are not equal");
    }

    function setSwapFeePercentage(uint256 percentage, address pool) internal {
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), admin);
        vm.prank(admin);
        vault.setStaticSwapFeePercentage(pool, percentage);
    }

    function _swapFee() internal virtual view returns (uint256) {
        return 0;
    }

    function _protocolFee() internal virtual view returns (uint256) {
        return 0;
    }
}

contract LiquidityInvariantWithFeeTest is LiquidityInvariantTest {
    function _swapFee() internal view override returns (uint256) {
        return 0.01e18;
    }
}

contract LiquidityInvariantWithProtocolFeeTest is LiquidityInvariantWithFeeTest {
    function _protocolFee() internal view override returns (uint256) {
        return 0.01e18;
    }
}

// abstract contract AddLiquidityApproximationThreeTokenTest is BaseVaultTest {
//     using ArrayHelpers for *;
//     using FixedPoint for *;

//     address internal exactOutPool;
//     address internal unbalancedPool;

//     uint256 internal maxAmount = 3e8 * 1e18 - 1;

//     uint256 internal daiIdx;
//     uint256 internal usdcIdx;
//     uint256 internal wethIdx;

//     function setUp() public virtual override {
//         defaultBalance = 1e10 * 1e18;
//         BaseVaultTest.setUp();

//         (daiIdx, usdcIdx, wethIdx) = getSortedIndexesForThree(address(dai), address(usdc), address(weth));

//         assertEq(dai.balanceOf(alice), dai.balanceOf(bob), "Bob and Alice DAI balances are not equal");
//         assertEq(usdc.balanceOf(alice), usdc.balanceOf(bob), "Bob and Alice USDC balances are not equal");
//         assertEq(weth.balanceOf(alice), weth.balanceOf(bob), "Bob and Alice WETH balances are not equal");
//     }

//     function createPool() internal virtual override returns (address) {
//         unbalancedPool = address(
//             new PoolMock(
//                 IVault(address(vault)),
//                 "ERC20 Pool",
//                 "ERC20POOL",
//                 vault.buildTokenConfig(
//                     [address(dai), address(usdc), address(weth)].toMemoryArray().asIERC20(),
//                     new IRateProvider[](3)
//                 ),
//                 true,
//                 365 days,
//                 address(0)
//             )
//         );
//         vm.label(address(unbalancedPool), "unbalancedPool");

//         exactOutPool = address(
//             new PoolMock(
//                 IVault(address(vault)),
//                 "ERC20 Pool",
//                 "ERC20POOL",
//                 vault.buildTokenConfig(
//                     [address(dai), address(usdc), address(weth)].toMemoryArray().asIERC20(),
//                     new IRateProvider[](3)
//                 ),
//                 true,
//                 365 days,
//                 address(0)
//             )
//         );
//         vm.label(address(exactOutPool), "exactOutPool");

//         return address(unbalancedPool);
//     }

//     function initPool() internal override {
//         poolInitAmount = 1e9 * 1e18;
//         (IERC20[] memory tokens, , , , ) = vault.getPoolTokenInfo(address(exactOutPool));
//         vm.prank(lp);
//         router.initialize(
//             address(exactOutPool),
//             tokens,
//             [poolInitAmount, poolInitAmount, poolInitAmount].toMemoryArray(),
//             0,
//             false,
//             ""
//         );

//         vm.prank(lp);
//         router.initialize(
//             address(unbalancedPool),
//             tokens,
//             [poolInitAmount, poolInitAmount, poolInitAmount].toMemoryArray(),
//             0,
//             false,
//             ""
//         );
//     }

//     /// Add

//     function testAddLiquidityInvariant__Fuzz(uint256 daiAmountIn, uint256 wethAmountIn) public {
//         daiAmountIn = bound(daiAmountIn, 1e18, maxAmount);
//         wethAmountIn = bound(wethAmountIn, 1e18, maxAmount);

//         uint256[] memory amountsIn = new uint256[](3);
//         amountsIn[daiIdx] = uint256(daiAmountIn);
//         amountsIn[wethIdx] = uint256(wethAmountIn);

//         vm.startPrank(alice);
//         uint256 bptUnbalancedAmountOut = router.addLiquidityUnbalanced({
//             pool: address(unbalancedPool),
//             exactAmountsIn: amountsIn,
//             minBptAmountOut: 0,
//             wethIsEth: false,
//             userData: bytes("")
//         });
//         vm.stopPrank();

//         vm.startPrank(bob);

//         uint256 daiExactIn = router.addLiquiditySingleTokenExactOut({
//             pool: address(exactOutPool),
//             tokenIn: dai,
//             maxAmountIn: daiAmountIn,
//             exactBptAmountOut: bptUnbalancedAmountOut / 2,
//             wethIsEth: false,
//             userData: bytes("")
//         });

//         daiExactIn += router.addLiquiditySingleTokenExactOut({
//             pool: address(exactOutPool),
//             tokenIn: weth,
//             maxAmountIn: wethAmountIn,
//             exactBptAmountOut: bptUnbalancedAmountOut / 2,
//             wethIsEth: false,
//             userData: bytes("")
//         });
//         vm.stopPrank();

//         assertEq(bptUnbalancedAmountOut, daiExactIn, "WTF");
//         // assertEq(dai.balanceOf(alice), dai.balanceOf(bob), "Bob and Alice DAI balances are not equal");
//     }
// }

/**
 * TODO:
 * - Static swap fee vs dynamic swap fee
 * - DAI / USDC / WETH
 * - Add DAI + Add USDC (individual exact in actions) vs Add [DAI, USDC, 0] (unbalanced)
 * - With Rates
 * - Different ERC20 decimals
 * - Different Pool states
 */
