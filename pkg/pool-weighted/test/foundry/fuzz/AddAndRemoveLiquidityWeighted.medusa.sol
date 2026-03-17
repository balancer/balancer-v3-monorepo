// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import {
    AddAndRemoveLiquidityMedusaTest
} from "@balancer-labs/v3-vault/test/foundry/fuzz/AddAndRemoveLiquidity.medusa.sol";

import { WeightedPoolFactory } from "../../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../../contracts/WeightedPool.sol";

contract AddAndRemoveLiquidityWeightedMedusaTest is AddAndRemoveLiquidityMedusaTest {
    uint256 internal constant DEFAULT_SWAP_FEE = 1e16;

    uint256 internal constant _WEIGHT1 = 33e16;
    uint256 internal constant _WEIGHT2 = 33e16;

    constructor() AddAndRemoveLiquidityMedusaTest() {
        // pow() rounding noise is relative to balance magnitude. At small balances the absolute wei error in
        // getBptRate() can exceed any fixed threshold. Scale tolerance to initial rate.
        //
        // A 1e-14 relative tolerance at initialRate=1e18 gives maxRateTolerance=1e4, which accommodates the
        // observed wobble at any pool size the fuzzer can reach.

        maxRateTolerance = initialRate / 1e14;
    }

    function createPool(
        IERC20[] memory tokens,
        uint256[] memory initialBalances
    ) internal virtual override returns (address) {
        uint256[] memory weights = new uint256[](3);
        weights[0] = _WEIGHT1;
        weights[1] = _WEIGHT2;
        // Sum of weights should equal 100%.
        weights[2] = 100e16 - (weights[0] + weights[1]);

        WeightedPoolFactory factory = new WeightedPoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            "Pool v1"
        );
        PoolRoleAccounts memory roleAccounts;

        WeightedPool newPool = WeightedPool(
            factory.create(
                "Weighted Pool",
                "WP",
                vault.buildTokenConfig(tokens),
                weights,
                roleAccounts,
                DEFAULT_SWAP_FEE, // Swap fee is set to 0 in the test constructor
                address(0), // No hooks
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                // NOTE: sends a unique salt.
                bytes32(poolCreationNonce++)
            )
        );

        // Cannot set the pool creator directly on a standard Balancer weighted pool factory.
        vault.manualSetPoolCreator(address(newPool), lp);

        // Initialize liquidity of weighted pool.
        medusa.prank(lp);
        router.initialize(address(newPool), tokens, initialBalances, 0, false, bytes(""));

        return address(newPool);
    }

    function computeRemoveAndAddLiquiditySingleToken(uint256 tokenIndex, uint256 tokenAmountOut) public override {
        tokenIndex = boundTokenIndex(tokenIndex);
        tokenAmountOut = boundTokenAmountOut(tokenAmountOut, tokenIndex);
        if (tokenAmountOut == 0) return;

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        medusa.prank(lp);
        uint256 bptAmountIn = router.removeLiquiditySingleTokenExactOut(
            address(pool),
            type(uint128).max,
            tokens[tokenIndex],
            tokenAmountOut,
            false,
            bytes("")
        );
        uint256[] memory exactAmountsIn = new uint256[](vault.getPoolTokens(address(pool)).length);
        exactAmountsIn[tokenIndex] = tokenAmountOut;

        medusa.prank(lp);
        uint256 bptAmountOut = router.addLiquidityUnbalanced(address(pool), exactAmountsIn, 0, false, bytes(""));
        bptProfit += int256(bptAmountOut) - int256(bptAmountIn);
    }

    function boundTokenDeposit(uint256 tokenAmountIn, uint256 tokenIndex) internal view override returns (uint256) {
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));
        // Cap at 3% of pool balance — well within the ~30% invariant ratio limit for weighted pools
        uint256 maxDeposit = balancesRaw[tokenIndex] / 33;
        uint256 lpBalance = BalancerPoolToken(address(pool)).balanceOf(lp);
        maxDeposit = maxDeposit < lpBalance ? maxDeposit : lpBalance;
        if (maxDeposit < _MINIMUM_TRADE_AMOUNT) return 0;
        return bound(tokenAmountIn, 0, maxDeposit);
    }

    function boundBptMint(uint256 bptAmount) internal view override returns (uint256) {
        uint256 totalSupply = BalancerPoolToken(address(pool)).totalSupply();
        // 3% of supply max — proportional adds scale linearly with BPT,
        // but single-token adds are much more constrained on weighted pools
        uint256 maxMint = totalSupply / 33;
        if (maxMint < _MINIMUM_TRADE_AMOUNT) return _MINIMUM_TRADE_AMOUNT;
        return bound(bptAmount, _MINIMUM_TRADE_AMOUNT, maxMint);
    }

    function boundBptBurn(uint256 bptAmt) internal view override returns (uint256) {
        uint256 totalSupply = BalancerPoolToken(address(pool)).totalSupply();
        uint256 lpBalance = BalancerPoolToken(address(pool)).balanceOf(lp);
        // 1% max burn — InvariantRatioBelowMin hits fast on weighted pools
        uint256 maxBurn = totalSupply / 100;
        if (maxBurn > lpBalance) maxBurn = lpBalance;
        if (maxBurn < _MINIMUM_TRADE_AMOUNT) return 0;
        return bound(bptAmt, _MINIMUM_TRADE_AMOUNT, maxBurn);
    }

    function boundTokenAmountOut(uint256 tokenAmountOut, uint256 tokenIndex) internal view override returns (uint256) {
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));
        uint256 maxOut = balancesRaw[tokenIndex] / 50; // 2% max for weighted pools
        if (maxOut < _MINIMUM_TRADE_AMOUNT) return 0;
        return bound(tokenAmountOut, _MINIMUM_TRADE_AMOUNT, maxOut);
    }
}
