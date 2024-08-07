// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { BasePoolTest } from "@balancer-labs/v3-vault/test/foundry/utils/BasePoolTest.sol";

import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../contracts/StablePool.sol";

contract StablePoolTest is BasePoolTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint256 constant DEFAULT_AMP_FACTOR = 200;
    uint256 constant TOKEN_AMOUNT = 1e3 * 1e18;

    function setUp() public virtual override {
        expectedAddLiquidityBptAmountOut = TOKEN_AMOUNT * 2;

        BasePoolTest.setUp();
    }

    function createPool() internal override returns (address) {
        factory = new StablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");

        TokenConfig[] memory tokenConfigs = new TokenConfig[](2);
        IERC20[] memory sortedTokens = InputHelpers.sortTokens(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );
        for (uint256 i = 0; i < sortedTokens.length; i++) {
            poolTokens.push(sortedTokens[i]);
            tokenConfigs[i].token = sortedTokens[i];

            tokenAmounts.push(TOKEN_AMOUNT);
        }

        PoolRoleAccounts memory roleAccounts;
        // Allow pools created by `factory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        address stablePool = address(
            StablePool(
                StablePoolFactory(address(factory)).create(
                    "ERC20 Pool",
                    "ERC20POOL",
                    tokenConfigs,
                    DEFAULT_AMP_FACTOR,
                    roleAccounts,
                    MIN_SWAP_FEE,
                    poolHooksContract,
                    false, // Do not enable donations
                    false, // Do not disable unbalanced add/remove liquidity
                    ZERO_BYTES32
                )
            )
        );
        return stablePool;
    }

    function initPool() internal override {
        vm.prank(lp);
        bptAmountOut = router.initialize(
            pool,
            poolTokens,
            tokenAmounts,
            // Account for the precision loss
            expectedAddLiquidityBptAmountOut - BasePoolTest.DELTA,
            false,
            bytes("")
        );
    }

    function testGetBptRate() public {
        uint256 invariantBefore = StableMath.computeInvariant(
            DEFAULT_AMP_FACTOR * StableMath.AMP_PRECISION,
            [TOKEN_AMOUNT, TOKEN_AMOUNT].toMemoryArray()
        );
        uint256 invariantAfter = StableMath.computeInvariant(
            DEFAULT_AMP_FACTOR * StableMath.AMP_PRECISION,
            [2 * TOKEN_AMOUNT, TOKEN_AMOUNT].toMemoryArray()
        );

        uint256[] memory amountsIn = [TOKEN_AMOUNT, 0].toMemoryArray();
        _testGetBptRate(invariantBefore, invariantAfter, amountsIn);
    }
}
