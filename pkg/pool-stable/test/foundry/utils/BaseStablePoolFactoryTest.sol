// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";

import { StablePoolContractsDeployer } from "./StablePoolContractsDeployer.sol";

/**
 * @notice Shared tests for factories that deploy standard Stable Pools.
 * @dev These tests apply to any factory whose pools are standard Stable Pools (e.g., `StablePoolFactory` and
 * `UnpausableStablePoolFactory`). Concrete test contracts deploy the factory under test in `setUp`, and implement
 * `createStablePool`.
 */
abstract contract BaseStablePoolFactoryTest is BaseVaultTest, StablePoolContractsDeployer {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    // Maximum swap fee of 10%.
    uint64 public constant MAX_SWAP_FEE_PERCENTAGE = 10e16;

    uint256 internal constant DEFAULT_AMP_FACTOR = 200;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        super.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    /**
     * @dev Create a pool from the factory under test, with the default amp factor and maximum swap fee, no hooks,
     * and unbalanced liquidity enabled.
     */
    function createStablePool(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokenConfig,
        PoolRoleAccounts memory roleAccounts,
        bool enableDonation
    ) internal virtual returns (address);

    function testCreatePoolWithoutDonation() public {
        address stablePool = _deployAndInitializeStablePool(false);

        // Try to donate but fails because pool does not support donations.
        vm.prank(bob);
        vm.expectRevert(IVaultErrors.DoesNotSupportDonation.selector);
        router.donate(stablePool, [poolInitAmount, poolInitAmount].toMemoryArray(), false, bytes(""));
    }

    function testCreatePoolWithDonation() public {
        uint256 amountToDonate = poolInitAmount;

        address stablePool = _deployAndInitializeStablePool(true);

        HookTestLocals memory vars = _createHookTestLocals(stablePool);

        // Donates to pool successfully.
        vm.prank(bob);
        router.donate(stablePool, [amountToDonate, amountToDonate].toMemoryArray(), false, bytes(""));

        _fillAfterHookTestLocals(vars, stablePool);

        // Bob balances.
        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, amountToDonate, "Bob DAI balance is wrong");
        assertEq(vars.bob.usdcBefore - vars.bob.usdcAfter, amountToDonate, "Bob USDC balance is wrong");
        assertEq(vars.bob.bptAfter, vars.bob.bptBefore, "Bob BPT balance is wrong");

        // Pool balances.
        assertEq(vars.poolAfter[daiIdx] - vars.poolBefore[daiIdx], amountToDonate, "Pool DAI balance is wrong");
        assertEq(vars.poolAfter[usdcIdx] - vars.poolBefore[usdcIdx], amountToDonate, "Pool USDC balance is wrong");
        assertEq(vars.bptSupplyAfter, vars.bptSupplyBefore, "Pool BPT supply is wrong");

        // Vault Balances.
        assertEq(vars.vault.daiAfter - vars.vault.daiBefore, amountToDonate, "Vault DAI balance is wrong");
        assertEq(vars.vault.usdcAfter - vars.vault.usdcBefore, amountToDonate, "Vault USDC balance is wrong");
    }

    function testCreatePoolWithTooManyTokens() public {
        IERC20[] memory bigPoolTokens = new IERC20[](StableMath.MAX_STABLE_TOKENS + 1);
        for (uint256 i = 0; i < bigPoolTokens.length; ++i) {
            bigPoolTokens[i] = createERC20(string.concat("TKN", Strings.toString(i)), 18);
        }

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(bigPoolTokens);
        PoolRoleAccounts memory roleAccounts;

        vm.expectRevert(IVaultErrors.MaxTokens.selector);
        createStablePool("Big Pool", "TOO_BIG", tokenConfig, roleAccounts, false);
    }

    function _deployAndInitializeStablePool(bool supportsDonation) internal returns (address) {
        PoolRoleAccounts memory roleAccounts;
        IERC20[] memory tokens = [address(dai), address(usdc)].toMemoryArray().asIERC20();

        address stablePool = createStablePool(
            supportsDonation ? "Pool With Donation" : "Pool Without Donation",
            supportsDonation ? "PwD" : "PwoD",
            vault.buildTokenConfig(tokens),
            roleAccounts,
            supportsDonation
        );

        // Initialize pool.
        vm.prank(lp);
        router.initialize(stablePool, tokens, [poolInitAmount, poolInitAmount].toMemoryArray(), 0, false, bytes(""));

        return stablePool;
    }

    struct WalletState {
        uint256 daiBefore;
        uint256 daiAfter;
        uint256 usdcBefore;
        uint256 usdcAfter;
        uint256 bptBefore;
        uint256 bptAfter;
    }

    struct HookTestLocals {
        WalletState bob;
        WalletState hook;
        WalletState vault;
        uint256[] poolBefore;
        uint256[] poolAfter;
        uint256 bptSupplyBefore;
        uint256 bptSupplyAfter;
    }

    function _createHookTestLocals(address pool) private view returns (HookTestLocals memory vars) {
        vars.bob.daiBefore = dai.balanceOf(bob);
        vars.bob.usdcBefore = usdc.balanceOf(bob);
        vars.bob.bptBefore = IERC20(pool).balanceOf(bob);
        vars.vault.daiBefore = dai.balanceOf(address(vault));
        vars.vault.usdcBefore = usdc.balanceOf(address(vault));
        vars.poolBefore = vault.getRawBalances(pool);
        vars.bptSupplyBefore = BalancerPoolToken(pool).totalSupply();
    }

    function _fillAfterHookTestLocals(HookTestLocals memory vars, address pool) private view {
        vars.bob.daiAfter = dai.balanceOf(bob);
        vars.bob.usdcAfter = usdc.balanceOf(bob);
        vars.bob.bptAfter = IERC20(pool).balanceOf(bob);
        vars.vault.daiAfter = dai.balanceOf(address(vault));
        vars.vault.usdcAfter = usdc.balanceOf(address(vault));
        vars.poolAfter = vault.getRawBalances(pool);
        vars.bptSupplyAfter = BalancerPoolToken(pool).totalSupply();
    }
}
