// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { BasePoolTest } from "@balancer-labs/v3-vault/test/foundry/utils/BasePoolTest.sol";

import { WeightedPoolFactory } from "../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";
import { WeightedPoolContractsDeployer } from "./utils/WeightedPoolContractsDeployer.sol";

contract BigWeightedPoolTest is WeightedPoolContractsDeployer, BasePoolTest {
    uint256 constant DEFAULT_SWAP_FEE = 1e16; // 1%
    uint256 constant TOKEN_AMOUNT = 1e3 * 1e18;

    uint256[] internal weights;

    function setUp() public virtual override {
        expectedAddLiquidityBptAmountOut = TOKEN_AMOUNT;
        tokenAmountIn = TOKEN_AMOUNT / 4;
        isTestSwapFeeEnabled = false;

        tokenIndexIn = 3;
        tokenIndexOut = 7;

        BasePoolTest.setUp();

        poolMinSwapFeePercentage = 0.001e16; // 0.001%
        poolMaxSwapFeePercentage = 10e16;
    }

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "ERC20 Pool";
        string memory symbol = "ERC20POOL";
        string memory poolVersion = "Pool v1";

        factory = deployWeightedPoolFactory(IVault(address(vault)), 365 days, "Factory v1", poolVersion);
        PoolRoleAccounts memory roleAccounts;

        uint256 numTokens = vault.getMaximumPoolTokens();
        IERC20[] memory bigPoolTokens = new IERC20[](numTokens);
        weights = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            // Use all 18-decimal tokens, for simplicity.
            bigPoolTokens[i] = createERC20(string.concat("TKN", Strings.toString(i)), 18);
            ERC20TestToken(address(bigPoolTokens[i])).mint(lp, defaultBalance);
            ERC20TestToken(address(bigPoolTokens[i])).mint(bob, defaultBalance);
            weights[i] = 1e18 / numTokens;
        }

        // Allow pools created by `factory` to use PoolHooksMock hooks.
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        newPool = WeightedPoolFactory(address(factory)).create(
            name,
            symbol,
            vault.buildTokenConfig(bigPoolTokens),
            weights,
            roleAccounts,
            DEFAULT_SWAP_FEE,
            poolHooksContract,
            false, // Do not enable donations
            false, // Do not disable unbalanced add/remove liquidity
            ZERO_BYTES32
        );
        vm.label(newPool, "Big weighted pool");

        // poolArgs is used to check pool deployment address with create2.
        poolArgs = abi.encode(
            WeightedPool.NewPoolParams({
                name: name,
                symbol: symbol,
                numTokens: bigPoolTokens.length,
                normalizedWeights: weights,
                version: poolVersion
            }),
            vault
        );

        // Get the sorted list of tokens.
        bigPoolTokens = vault.getPoolTokens(address(newPool));
        for (uint256 i = 0; i < bigPoolTokens.length; ++i) {
            poolTokens.push(bigPoolTokens[i]);
            tokenAmounts.push(TOKEN_AMOUNT);
        }

        _approveForPool(IERC20(address(newPool)));
    }

    function _approveForSender() internal {
        for (uint256 i = 0; i < poolTokens.length; ++i) {
            poolTokens[i].approve(address(permit2), type(uint256).max);
            permit2.approve(address(poolTokens[i]), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(poolTokens[i]), address(batchRouter), type(uint160).max, type(uint48).max);
        }
    }

    function _approveForPool(IERC20 bpt) internal {
        for (uint256 i = 0; i < users.length; ++i) {
            vm.startPrank(users[i]);

            _approveForSender();

            bpt.approve(address(router), type(uint256).max);
            bpt.approve(address(batchRouter), type(uint256).max);

            IERC20(bpt).approve(address(permit2), type(uint256).max);
            permit2.approve(address(bpt), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(bpt), address(batchRouter), type(uint160).max, type(uint48).max);
            vm.stopPrank();
        }
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
}
