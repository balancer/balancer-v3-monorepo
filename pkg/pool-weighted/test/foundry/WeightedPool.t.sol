// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { TokenConfig, PoolConfig, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { Vault } from "@balancer-labs/v3-vault/contracts/Vault.sol";
import { PoolConfigBits } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";
import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";

import { WeightedPoolFactory } from "../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";

import { BasePoolTest } from "@balancer-labs/v3-vault/test/foundry/utils/BasePoolTest.t.sol";

contract WeightedPoolTest is BasePoolTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 constant DEFAULT_SWAP_FEE = 1e16; // 1%
    uint256 constant TOKEN_AMOUNT = 1e3 * 1e18;

    uint256[] internal weights;

    function setUp() public virtual override {
        expectedAddLiquidityBptAmountOut = TOKEN_AMOUNT;
        tokenAmountIn = TOKEN_AMOUNT / 4;
        isTestSwapFeeEnabled = false;
        BasePoolTest.setUp();
    }

    function _createPool(address[] memory tokens, string memory label) internal virtual override returns (address) {
        poolTokens.push(dai);
        tokenAmounts.push(TOKEN_AMOUNT);

        poolTokens.push(usdc);
        tokenAmounts.push(TOKEN_AMOUNT);

        factory = new WeightedPoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
        PoolRoleAccounts memory roleAccounts;

        weights = [uint256(0.50e18), uint256(0.50e18)].toMemoryArray();

        // Allow pools created by `factory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        WeightedPool newPool = WeightedPool(
            WeightedPoolFactory(address(factory)).create(
                "ERC20 Pool",
                "ERC20POOL",
                vault.buildTokenConfig(tokens.asIERC20()),
                weights,
                roleAccounts,
                DEFAULT_SWAP_FEE,
                poolHooksContract,
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                ZERO_BYTES32
            )
        );
        vm.label(address(newPool), label);
        return address(newPool);
    }

    function initPool() internal override {
        vm.startPrank(lp);
        bptAmountOut = _initPool(
            pool,
            tokenAmounts,
            // Account for the precision loss
            expectedAddLiquidityBptAmountOut - DELTA
        );
        vm.stopPrank();
    }

    function testGetBptRate() public {
        uint256 invariantBefore = WeightedMath.computeInvariant(weights, [TOKEN_AMOUNT, TOKEN_AMOUNT].toMemoryArray());
        uint256 invariantAfter = WeightedMath.computeInvariant(
            weights,
            [2 * TOKEN_AMOUNT, TOKEN_AMOUNT].toMemoryArray()
        );

        uint256[] memory amountsIn = [TOKEN_AMOUNT, 0].toMemoryArray();
        _testGetBptRate(invariantBefore, invariantAfter, amountsIn);
    }

    function testFailSwapFeeTooLow() public {
        TokenConfig[] memory tokens = new TokenConfig[](2);
        PoolRoleAccounts memory roleAccounts;
        tokens[0].token = IERC20(dai);
        tokens[1].token = IERC20(usdc);

        address lowFeeWeightedPool = WeightedPoolFactory(address(factory)).create(
            "ERC20 Pool",
            "ERC20POOL",
            tokens,
            [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
            roleAccounts,
            MIN_SWAP_FEE - 1, // Swap fee too low
            poolHooksContract,
            false, // Do not enable donations
            false, // Do not disable unbalanced add/remove liquidity
            ZERO_BYTES32
        );

        factoryMock.registerTestPool(lowFeeWeightedPool, tokens);
    }
}
