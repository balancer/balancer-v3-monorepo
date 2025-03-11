// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { console } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { GyroPoolMath } from "@balancer-labs/v3-pool-gyro/contracts/lib/GyroPoolMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IAclAmmPool } from "@balancer-labs/v3-interfaces/contracts/pool-aclamm/IAclAmmPool.sol";

import { BaseAclAmmTest } from "./utils/BaseAclAmmTest.sol";
import { AclAmmPool } from "../../contracts/AclAmmPool.sol";
import { AclAmmMath } from "../../contracts/lib/AclAmmMath.sol";

contract AclAmmPoolVirtualBalancesTest is BaseAclAmmTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 internal constant maxPrice = 4000;
    uint256 internal constant minPrice = 2000;
    uint256 internal constant initialABalance = 1_000_000e18;
    uint256 internal constant initialBBalance = 100_000e18;

    function setUp() public virtual override {
        setSqrtQ0(minPrice, maxPrice);
        setInitialBalances(initialABalance, initialBBalance);
        setIncreaseDayRate(0);
        super.setUp();
    }

    function testInitialParams() public view {
        uint256[] memory virtualBalances = _calculateVirtualBalances();

        uint256[] memory curentVirtualBalances = AclAmmPool(pool).getLastVirtualBalances();

        assertEq(AclAmmPool(pool).getCurrentSqrtQ0(), sqrtQ0(), "Invalid sqrtQ0");
        assertEq(curentVirtualBalances[0], virtualBalances[0], "Invalid virtual A balance");
        assertEq(curentVirtualBalances[1], virtualBalances[1], "Invalid virtual B balance");
    }

    function testWithDifferentInitialBalances_Fuzz(int256 diffCoefficient) public {
        // This test verifies the virtual balances of two pools, where the real balances
        // differ by a certain coefficient while maintaining the balance ratio.

        diffCoefficient = bound(diffCoefficient, -100, 100);
        if (diffCoefficient >= -1 && diffCoefficient <= 1) {
            diffCoefficient = 2;
        }

        uint256[] memory newInitialBalances = new uint256[](2);
        if (diffCoefficient > 0) {
            newInitialBalances[0] = initialABalance * uint256(diffCoefficient);
            newInitialBalances[1] = initialBBalance * uint256(diffCoefficient);
        } else {
            newInitialBalances[0] = initialABalance / uint256(-diffCoefficient);
            newInitialBalances[1] = initialBBalance / uint256(-diffCoefficient);
        }

        setInitialBalances(newInitialBalances[0], newInitialBalances[1]);
        (address firstPool, address secondPool) = _createNewPool();

        assertEq(AclAmmPool(firstPool).getCurrentSqrtQ0(), sqrtQ0(), "Invalid sqrtQ0 for firstPool");
        assertEq(AclAmmPool(secondPool).getCurrentSqrtQ0(), sqrtQ0(), "Invalid sqrtQ0 for newPool");

        uint256[] memory curentFirstPoolVirtualBalances = AclAmmPool(firstPool).getLastVirtualBalances();
        uint256[] memory curentNewPoolVirtualBalances = AclAmmPool(secondPool).getLastVirtualBalances();

        if (diffCoefficient > 0) {
            assertGt(
                curentNewPoolVirtualBalances[0],
                curentFirstPoolVirtualBalances[0],
                "Virtual A balance should be greater for newPool"
            );
            assertGt(
                curentNewPoolVirtualBalances[1],
                curentFirstPoolVirtualBalances[1],
                "Virtual B balance should be greater for newPool"
            );
        } else {
            assertLt(
                curentNewPoolVirtualBalances[0],
                curentFirstPoolVirtualBalances[0],
                "Virtual A balance should be less for newPool"
            );
            assertLt(
                curentNewPoolVirtualBalances[1],
                curentFirstPoolVirtualBalances[1],
                "Virtual B balance should be less for newPool"
            );
        }
    }

    function testWithDifferentPriceRange_Fuzz(uint256 newSqrtQ) public {
        newSqrtQ = bound(newSqrtQ, 1.4e18, 1_000_000e18);

        uint256 initialSqrtQ = sqrtQ0();
        setSqrtQ0(newSqrtQ);
        (address firstPool, address secondPool) = _createNewPool();

        uint256[] memory curentFirstPoolVirtualBalances = AclAmmPool(firstPool).getLastVirtualBalances();
        uint256[] memory curentNewPoolVirtualBalances = AclAmmPool(secondPool).getLastVirtualBalances();

        if (newSqrtQ > initialSqrtQ) {
            assertLt(
                curentNewPoolVirtualBalances[0],
                curentFirstPoolVirtualBalances[0],
                "Virtual A balance should be less for newPool"
            );
            assertLt(
                curentNewPoolVirtualBalances[1],
                curentFirstPoolVirtualBalances[1],
                "Virtual B balance should be less for newPool"
            );
        } else {
            assertGe(
                curentNewPoolVirtualBalances[0],
                curentFirstPoolVirtualBalances[0],
                "Virtual A balance should be greater for newPool"
            );
            assertGe(
                curentNewPoolVirtualBalances[1],
                curentFirstPoolVirtualBalances[1],
                "Virtual B balance should be greater for newPool"
            );
        }
    }

    function testChangingDifferentPriceRange_Fuzz(uint256 newSqrtQ) public {
        newSqrtQ = bound(newSqrtQ, 1.4e18, 1_000_000e18);

        uint256 initialSqrtQ = sqrtQ0();

        uint256 duration = 2 hours;

        uint256[] memory poolVirtualBalancesBefore = AclAmmPool(pool).getLastVirtualBalances();

        uint256 currentTimestamp = block.timestamp;

        vm.prank(admin);
        AclAmmPool(pool).setSqrtQ0(initialSqrtQ, currentTimestamp, currentTimestamp + duration);
        skip(duration);

        uint256[] memory poolVirtualBalancesAfter = AclAmmPool(pool).getLastVirtualBalances();

        if (newSqrtQ > initialSqrtQ) {
            assertLt(
                poolVirtualBalancesAfter[0],
                poolVirtualBalancesBefore[0],
                "Virtual A balance after should be less than before"
            );
            assertLt(
                poolVirtualBalancesAfter[1],
                poolVirtualBalancesBefore[1],
                "Virtual B balance after should be less than before"
            );
        } else {
            assertGe(
                poolVirtualBalancesAfter[0],
                poolVirtualBalancesBefore[0],
                "Virtual A balance after should be greater than before"
            );
            assertGe(
                poolVirtualBalancesAfter[1],
                poolVirtualBalancesBefore[1],
                "Virtual B balance after should be greater than before"
            );
        }
    }

    function testSwap_Fuzz(uint256 exactAmountIn) public {
        exactAmountIn = bound(exactAmountIn, 1e18, 10_000e18);

        uint256[] memory virtualBalances = _calculateVirtualBalances();
        uint256 invariantBefore = _getCurrentInvariant();

        vm.prank(alice);
        router.swapSingleTokenExactIn(pool, dai, usdc, exactAmountIn, 1, UINT256_MAX, false, new bytes(0));

        uint256 invariantAfter = _getCurrentInvariant();
        assertEq(invariantBefore, invariantAfter, "Invariant should not change");

        uint256[] memory curentVirtualBalances = AclAmmPool(pool).getLastVirtualBalances();
        assertEq(curentVirtualBalances[0], virtualBalances[0], "Virtual A balances don't equal");
        assertEq(curentVirtualBalances[1], virtualBalances[1], "Virtual B balances don't equal");
    }

    function testAddLiquidity_Fuzz(uint256 exactBptAmountOut) public {
        exactBptAmountOut = bound(exactBptAmountOut, 1e18, 10_000e18);

        uint256 invariantBefore = _getCurrentInvariant();

        vm.prank(alice);
        router.addLiquidityProportional(
            pool,
            [MAX_UINT128, MAX_UINT128].toMemoryArray(),
            exactBptAmountOut,
            false,
            new bytes(0)
        );

        uint256 invariantAfter = _getCurrentInvariant();

        assertGt(invariantAfter, invariantBefore, "Invariant should increase");

        // TODO: add check for virtual balances
    }

    function testRemoveLiquidity_Fuzz(uint256 exactBptAmountIn) public {
        exactBptAmountIn = bound(exactBptAmountIn, 1e18, 10_000e18);

        uint256 invariantBefore = _getCurrentInvariant();

        vm.prank(lp);
        router.removeLiquidityProportional(
            pool,
            exactBptAmountIn,
            [uint256(1), 1].toMemoryArray(),
            false,
            new bytes(0)
        );

        uint256 invariantAfter = _getCurrentInvariant();
        assertLt(invariantAfter, invariantBefore, "Invariant should decrease");

        // TODO: add check for virtual balances
    }

    function _getCurrentInvariant() internal view returns (uint256) {
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(pool);
        return AclAmmPool(pool).computeInvariant(balances, Rounding.ROUND_DOWN);
    }

    function _calculateVirtualBalances() internal view returns (uint256[] memory virtualBalances) {
        virtualBalances = new uint256[](2);

        uint256 sqrtQMinusOne = sqrtQ0() - FixedPoint.ONE;
        virtualBalances[0] = initialABalance.divDown(sqrtQMinusOne);
        virtualBalances[1] = initialBBalance.divDown(sqrtQMinusOne);
    }

    function _createNewPool() internal returns (address initalPool, address newPool) {
        initalPool = pool;
        salt = keccak256(abi.encodePacked("test"));
        (pool, poolArguments) = createPool();
        approveForPool(IERC20(pool));
        initPool();
        newPool = pool;
    }
}
