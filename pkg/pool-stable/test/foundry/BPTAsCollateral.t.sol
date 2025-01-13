// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig, PoolRoleAccounts, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";

import { StablePoolContractsDeployer } from "./utils/StablePoolContractsDeployer.sol";
import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../contracts/StablePool.sol";

contract BPTAsCollateralTest is BaseVaultTest, StablePoolContractsDeployer {
    using ArrayHelpers for *;
    using CastingHelpers for address[];

    string internal constant POOL_VERSION = "Pool v1";
    uint256 internal constant DEFAULT_AMP_FACTOR = 200;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public override {
        super.setUp();
        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function createPoolFactory() internal override returns (address) {
        return address(deployStablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", POOL_VERSION));
    }

    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "Stable Pool";
        string memory symbol = "STABLE";

        TokenConfig[] memory tokenConfigs = new TokenConfig[](2);
        IERC20[] memory sortedTokens = InputHelpers.sortTokens(tokens.asIERC20());
        for (uint256 i = 0; i < sortedTokens.length; i++) {
            tokenConfigs[i].token = sortedTokens[i];
        }

        PoolRoleAccounts memory roleAccounts;
        // Allow pools created by `factory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(poolFactory);

        newPool = StablePoolFactory(poolFactory).create(
            name,
            symbol,
            tokenConfigs,
            DEFAULT_AMP_FACTOR,
            roleAccounts,
            BASE_MIN_SWAP_FEE,
            poolHooksContract,
            false, // Do not enable donations
            false, // Do not disable unbalanced add/remove liquidity
            ZERO_BYTES32
        );
        vm.label(newPool, label);

        // poolArgs is used to check pool deployment address with create2.
        poolArgs = abi.encode(
            StablePool.NewPoolParams({
                name: name,
                symbol: symbol,
                amplificationParameter: DEFAULT_AMP_FACTOR,
                version: POOL_VERSION
            }),
            vault
        );
    }

    function testAddAndRemoveLiquidityBptPrice__Fuzz(
        uint256 daiInitialBalance,
        uint256 usdcInitialBalance,
        uint256 amount,
        uint256 amountDelta
    ) public {
        // TODO Calculate min and max balance (use compute balance with current invariant * ratio)

        daiInitialBalance = bound(daiInitialBalance, 1e18, poolInitAmount);
        usdcInitialBalance = bound(usdcInitialBalance, 1e18, poolInitAmount);
        // Makes sure the invariant ratio limit is not trespassed.
        amount = bound(amount, daiInitialBalance / 100, (daiInitialBalance * 2) / 3);
        amountDelta = bound(amountDelta, 1, 1e18);

        uint256[] memory balances = new uint256[](2);
        balances[daiIdx] = daiInitialBalance;
        balances[usdcIdx] = usdcInitialBalance;

        vault.manualSetPoolBalances(pool, balances, balances);

        uint256 invariantBefore = StablePool(pool).computeInvariant(balances, Rounding.ROUND_DOWN);

        uint256[] memory amountsToAdd = new uint256[](2);
        amountsToAdd[daiIdx] = amount + amountDelta;

        vm.startPrank(lp);
        router.addLiquidityUnbalanced(pool, amountsToAdd, 0, false, bytes(""));
        router.removeLiquiditySingleTokenExactOut(pool, MAX_UINT128, dai, amount, false, bytes(""));
        vm.stopPrank();

        (, , uint256[] memory newBalances, ) = vault.getPoolTokenInfo(pool);
        uint256 invariantAfter = StablePool(pool).computeInvariant(newBalances, Rounding.ROUND_DOWN);

        assertGe(invariantAfter, invariantBefore);
    }
}
