// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { BasePoolMath } from "@balancer-labs/v3-vault/contracts/BasePoolMath.sol";

import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePoolContractsDeployer } from "./utils/StablePoolContractsDeployer.sol";

/**
 * @title StablePoolInvariantRatioBoundsTest
 * @notice Production-boundary tests for Stable pools: invariant ratio bounds are enforced by the Vault (BasePoolMath).
 * @dev This replaces any "local helper" imbalance checks: the production system constrains unbalanced liquidity by
 * checking the invariant ratio against pool-provided min/max bounds (StableMath.MIN/MAX_INVARIANT_RATIO).
 */
contract StablePoolInvariantRatioBoundsTest is StablePoolContractsDeployer, BaseVaultTest {
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;
    using ArrayHelpers for *;

    uint256 internal constant DEFAULT_AMP = 200;
    uint256 internal constant DEFAULT_SWAP_FEE = 1e12; // 0.0001%
    string internal constant POOL_VERSION = "Pool v1";

    StablePoolFactory internal stableFactory;
    uint256 internal poolCreationNonce;

    function setUp() public override {
        super.setUp();
        stableFactory = deployStablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", POOL_VERSION);
    }

    function testUnbalancedAddLiquidityAboveMaxInvariantRatioReverts() public {
        address pool = _createAndInitStablePool(DEFAULT_AMP, 1e21, 1e21);

        // Try to add an extreme amount of a single token to blow past MAX_INVARIANT_RATIO (500%).
        // This should be rejected by BasePoolMath.ensureInvariantRatioBelowMaximumBound in production.
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = 1000e21;
        amountsIn[1] = 0;

        // Foundry matches custom errors by full encoded revert data, so compute the exact expected args.
        PoolData memory poolData = vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_UP);
        uint256[] memory currentBalances = poolData.balancesLiveScaled18;

        uint256[] memory exactAmountsScaled18 = new uint256[](amountsIn.length);
        for (uint256 i = 0; i < amountsIn.length; ++i) {
            exactAmountsScaled18[i] = amountsIn[i].toScaled18ApplyRateRoundDown(
                poolData.decimalScalingFactors[i],
                poolData.tokenRates[i]
            );
        }

        uint256[] memory newBalances = new uint256[](currentBalances.length);
        for (uint256 i = 0; i < currentBalances.length; ++i) {
            newBalances[i] = currentBalances[i] + exactAmountsScaled18[i] - 1; // matches BasePoolMath
        }

        uint256 currentInvariant = IBasePool(pool).computeInvariant(currentBalances, Rounding.ROUND_UP);
        uint256 invariantRatio = IBasePool(pool).computeInvariant(newBalances, Rounding.ROUND_DOWN).divDown(
            currentInvariant
        );
        uint256 maxInvariantRatio = IBasePool(pool).getMaximumInvariantRatio();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(BasePoolMath.InvariantRatioAboveMax.selector, invariantRatio, maxInvariantRatio)
        );
        router.addLiquidityUnbalanced(pool, amountsIn, 0, false, bytes(""));
    }

    function testUnbalancedAddLiquidityWithinMaxInvariantRatioSucceedsAndRespectsBound() public {
        address pool = _createAndInitStablePool(DEFAULT_AMP, 1e22, 1e22);

        (, , , uint256[] memory scaledBefore) = vault.getPoolTokenInfo(pool);
        uint256 invBefore = IBasePool(pool).computeInvariant(scaledBefore, Rounding.ROUND_DOWN);

        // Moderate single-sided add: should succeed and keep invariant ratio below MAX bound.
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = 1e21;
        amountsIn[1] = 0;

        // Sanity-check the pool exposes the StableMath invariant ratio constants.
        assertEq(IBasePool(pool).getMaximumInvariantRatio(), StableMath.MAX_INVARIANT_RATIO, "Unexpected max ratio");
        assertEq(IBasePool(pool).getMinimumInvariantRatio(), StableMath.MIN_INVARIANT_RATIO, "Unexpected min ratio");

        uint256 bptBefore = IERC20(pool).balanceOf(alice);
        vm.prank(alice);
        router.addLiquidityUnbalanced(pool, amountsIn, 0, false, bytes(""));
        uint256 bptAfter = IERC20(pool).balanceOf(alice);
        assertGt(bptAfter, bptBefore, "Expected BPT minted");

        (, , , uint256[] memory scaledAfter) = vault.getPoolTokenInfo(pool);
        uint256 invAfter = IBasePool(pool).computeInvariant(scaledAfter, Rounding.ROUND_DOWN);
        uint256 invariantRatio = invAfter.divDown(invBefore);

        uint256 maxInvariantRatio = IBasePool(pool).getMaximumInvariantRatio();
        assertGt(invariantRatio, FixedPoint.ONE, "Invariant ratio should increase on add");
        assertLe(invariantRatio, maxInvariantRatio, "Invariant ratio should be <= max bound");
    }

    function testSingleTokenRemoveBelowMinInvariantRatioReverts() public {
        address pool = _createAndInitStablePool(DEFAULT_AMP, 1e22, 1e22);

        IERC20[] memory tokens = _getDefaultTokens();
        uint256 lpBpt = IERC20(pool).balanceOf(lp);

        // Request an extreme single-token withdrawal; should hit MIN_INVARIANT_RATIO (60%) bound.
        uint256 amountOut = 9e21; // 90% of one side

        // Compute the exact expected invariant ratio (and min bound) used by BasePoolMath.
        PoolData memory poolData = vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_UP);
        uint256[] memory currentBalances = poolData.balancesLiveScaled18;

        uint256 tokenOutIndex = 0; // tokens are sorted & registered in this order
        uint256 exactAmountOutScaled18 = amountOut.toScaled18ApplyRateRoundUp(
            poolData.decimalScalingFactors[tokenOutIndex],
            poolData.tokenRates[tokenOutIndex]
        );

        uint256[] memory newBalances = new uint256[](currentBalances.length);
        for (uint256 i = 0; i < currentBalances.length; ++i) {
            newBalances[i] = currentBalances[i] - 1; // matches BasePoolMath
        }
        newBalances[tokenOutIndex] = newBalances[tokenOutIndex] - exactAmountOutScaled18;

        uint256 currentInvariant = IBasePool(pool).computeInvariant(currentBalances, Rounding.ROUND_UP);
        uint256 invariantRatio = IBasePool(pool).computeInvariant(newBalances, Rounding.ROUND_UP).divUp(
            currentInvariant
        );
        uint256 minInvariantRatio = IBasePool(pool).getMinimumInvariantRatio();

        vm.startPrank(lp);
        IERC20(pool).approve(address(router), type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(BasePoolMath.InvariantRatioBelowMin.selector, invariantRatio, minInvariantRatio)
        );
        router.removeLiquiditySingleTokenExactOut(pool, lpBpt, tokens[0], amountOut, false, bytes(""));
        vm.stopPrank();
    }

    function testSingleTokenRemoveWithinMinInvariantRatioSucceedsAndRespectsBound() public {
        address pool = _createAndInitStablePool(DEFAULT_AMP, 1e22, 1e22);

        IERC20[] memory tokens = _getDefaultTokens();

        (, , , uint256[] memory scaledBefore) = vault.getPoolTokenInfo(pool);
        uint256 invBefore = IBasePool(pool).computeInvariant(scaledBefore, Rounding.ROUND_DOWN);

        // Small single-token withdrawal: should succeed and keep invariant ratio above MIN bound.
        uint256 amountOut = 1e21;

        uint256 lpBpt = IERC20(pool).balanceOf(lp);
        uint256 bptBefore = IERC20(pool).balanceOf(lp);

        vm.startPrank(lp);
        IERC20(pool).approve(address(router), type(uint256).max);
        router.removeLiquiditySingleTokenExactOut(pool, lpBpt, tokens[0], amountOut, false, bytes(""));
        vm.stopPrank();

        uint256 bptAfter = IERC20(pool).balanceOf(lp);
        assertLt(bptAfter, bptBefore, "Expected BPT burned");

        (, , , uint256[] memory scaledAfter) = vault.getPoolTokenInfo(pool);
        uint256 invAfter = IBasePool(pool).computeInvariant(scaledAfter, Rounding.ROUND_UP);
        uint256 invariantRatio = invAfter.divUp(invBefore);

        uint256 minInvariantRatio = IBasePool(pool).getMinimumInvariantRatio();
        assertLt(invariantRatio, FixedPoint.ONE, "Invariant ratio should decrease on remove");
        assertGe(invariantRatio, minInvariantRatio, "Invariant ratio should be >= min bound");
    }

    function _createAndInitStablePool(
        uint256 amp,
        uint256 balance0,
        uint256 balance1
    ) internal returns (address newPool) {
        IERC20[] memory tokens = _getDefaultTokens();

        PoolRoleAccounts memory roleAccounts;

        newPool = stableFactory.create(
            "Stable Pool",
            "STABLE",
            vault.buildTokenConfig(tokens),
            amp,
            roleAccounts,
            DEFAULT_SWAP_FEE,
            address(0),
            false,
            false,
            bytes32(poolCreationNonce++)
        );

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = balance0;
        amounts[1] = balance1;

        vm.prank(lp);
        router.initialize(newPool, tokens, amounts, 0, false, bytes(""));
    }

    function _getDefaultTokens() internal view returns (IERC20[] memory tokens) {
        tokens = new IERC20[](2);
        tokens[0] = dai;
        tokens[1] = usdc;
        tokens = InputHelpers.sortTokens(tokens);
    }
}
