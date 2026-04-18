// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";

import { StablePoolNoPauseFactory } from "../../contracts/StablePoolNoPauseFactory.sol";
import { StablePoolContractsDeployer } from "./utils/StablePoolContractsDeployer.sol";

contract StablePoolNoPauseFactoryTest is BaseVaultTest, StablePoolContractsDeployer {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    // Maximum swap fee of 10%.
    uint64 public constant MAX_SWAP_FEE_PERCENTAGE = 10e16;

    StablePoolNoPauseFactory internal stablePoolNoPauseFactory;

    // Timestamp at which the factory was deployed (captured in setUp).
    uint256 internal factoryDeployTime;

    uint256 internal constant DEFAULT_AMP_FACTOR = 200;

    function setUp() public override {
        super.setUp();

        factoryDeployTime = block.timestamp;
        stablePoolNoPauseFactory = new StablePoolNoPauseFactory(IVault(address(vault)), "Factory v1", "Pool v1");
        vm.label(address(stablePoolNoPauseFactory), "stable pool no-pause factory");

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    /***************************************************************************
                          Mirrored tests from StablePoolFactory
    ***************************************************************************/

    function testFactoryPausedState() public view {
        // Unlike the standard factory (365 days), this one is hardcoded to zero.
        assertEq(stablePoolNoPauseFactory.getPauseWindowDuration(), 0, "Pause window duration should be zero");
        assertEq(
            stablePoolNoPauseFactory.getOriginalPauseWindowEndTime(),
            factoryDeployTime,
            "Original pause window end time should equal the factory deploy timestamp"
        );
        // Because `block.timestamp >= _poolsPauseWindowEndTime` from the moment the factory is deployed,
        // `getNewPoolPauseWindowEndTime()` resolves to zero immediately.
        assertEq(
            stablePoolNoPauseFactory.getNewPoolPauseWindowEndTime(),
            0,
            "New-pool pause window end time should be zero"
        );
    }

    function testCreatePoolWithoutDonation() public {
        address stablePool = _deployAndInitializeStablePool(false);

        // Try to donate but fails because pool does not support donations
        vm.prank(bob);
        vm.expectRevert(IVaultErrors.DoesNotSupportDonation.selector);
        router.donate(stablePool, [poolInitAmount, poolInitAmount].toMemoryArray(), false, bytes(""));
    }

    function testCreatePoolWithDonation() public {
        uint256 amountToDonate = poolInitAmount;

        address stablePool = _deployAndInitializeStablePool(true);

        HookTestLocals memory vars = _createHookTestLocals(stablePool);

        // Donates to pool successfully
        vm.prank(bob);
        router.donate(stablePool, [amountToDonate, amountToDonate].toMemoryArray(), false, bytes(""));

        _fillAfterHookTestLocals(vars, stablePool);

        // Bob balances
        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, amountToDonate, "Bob DAI balance is wrong");
        assertEq(vars.bob.usdcBefore - vars.bob.usdcAfter, amountToDonate, "Bob USDC balance is wrong");
        assertEq(vars.bob.bptAfter, vars.bob.bptBefore, "Bob BPT balance is wrong");

        // Pool balances
        assertEq(vars.poolAfter[daiIdx] - vars.poolBefore[daiIdx], amountToDonate, "Pool DAI balance is wrong");
        assertEq(vars.poolAfter[usdcIdx] - vars.poolBefore[usdcIdx], amountToDonate, "Pool USDC balance is wrong");
        assertEq(vars.bptSupplyAfter, vars.bptSupplyBefore, "Pool BPT supply is wrong");

        // Vault Balances
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
        stablePoolNoPauseFactory.create(
            "Big Pool",
            "TOO_BIG",
            tokenConfig,
            DEFAULT_AMP_FACTOR,
            roleAccounts,
            MAX_SWAP_FEE_PERCENTAGE,
            address(0),
            false,
            false,
            ZERO_BYTES32
        );
    }

    /***************************************************************************
                           Unpauseable-specific assertions
    ***************************************************************************/

    function testNewPoolPauseWindowEndTimeStaysZero() public {
        // Right after deployment.
        assertEq(
            stablePoolNoPauseFactory.getNewPoolPauseWindowEndTime(),
            0,
            "getNewPoolPauseWindowEndTime should be zero immediately after deploy"
        );

        // Even far into the future.
        skip(365 days);
        assertEq(
            stablePoolNoPauseFactory.getNewPoolPauseWindowEndTime(),
            0,
            "getNewPoolPauseWindowEndTime should remain zero after warping forward"
        );
    }

    function testCreatedPoolHasZeroPauseWindowEndTime() public {
        address stablePool = _deployStablePoolWithPauseManager(admin);

        (bool poolPaused, uint32 poolPauseWindowEndTime, , address pauseManager) = vault.getPoolPausedState(
            stablePool
        );

        // Buffer period end time is intentionally not asserted here: it is computed from the Vault's buffer period
        // duration (independent of this factory) and is irrelevant because the pool can never enter a paused state.
        assertFalse(poolPaused, "Pool should not be paused at registration");
        assertEq(poolPauseWindowEndTime, 0, "Pool pause window end time should be zero");
        assertEq(pauseManager, admin, "Pause manager should be admin");
    }

    function testCannotPausePoolAsPauseManager() public {
        address stablePool = _deployStablePoolWithPauseManager(admin);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPauseWindowExpired.selector, stablePool));
        vault.pausePool(stablePool);
    }

    function testCannotPausePoolAsGovernance() public {
        // No pause manager; governance path via authorizer.
        address stablePool = _deployStablePoolWithPauseManager(address(0));

        bytes32 pausePoolRole = vault.getActionId(IVaultAdmin.pausePool.selector);
        authorizer.grantRole(pausePoolRole, alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPauseWindowExpired.selector, stablePool));
        vault.pausePool(stablePool);
    }

    function testCannotPausePoolSameBlockAsDeploy() public {
        // Deploy a fresh factory in this test (same block) and immediately register a pool - no vm.warp in between.
        StablePoolNoPauseFactory freshFactory = new StablePoolNoPauseFactory(
            IVault(address(vault)),
            "Factory v2",
            "Pool v2"
        );

        PoolRoleAccounts memory roleAccounts;
        roleAccounts.pauseManager = admin;
        IERC20[] memory tokens = [address(dai), address(usdc)].toMemoryArray().asIERC20();

        address stablePool = freshFactory.create(
            "Same Block Pool",
            "SBP",
            vault.buildTokenConfig(tokens),
            DEFAULT_AMP_FACTOR,
            roleAccounts,
            MAX_SWAP_FEE_PERCENTAGE,
            address(0),
            false,
            false,
            ZERO_BYTES32
        );

        (, uint32 poolPauseWindowEndTime, , ) = vault.getPoolPausedState(stablePool);
        assertEq(poolPauseWindowEndTime, 0, "Same-block pool pause window end time should be zero");

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPauseWindowExpired.selector, stablePool));
        vault.pausePool(stablePool);
    }

    function testUnauthenticatedPauseStillReverts() public {
        // Even without role/pauseManager, the Vault reverts with authentication, confirming the pool is not pausable
        // through an unauthorized path.
        address stablePool = _deployStablePoolWithPauseManager(admin);

        vm.prank(bob);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.pausePool(stablePool);
    }

    /***************************************************************************
                                      Helpers
    ***************************************************************************/

    function _deployAndInitializeStablePool(bool supportsDonation) private returns (address) {
        PoolRoleAccounts memory roleAccounts;
        IERC20[] memory tokens = [address(dai), address(usdc)].toMemoryArray().asIERC20();

        address stablePool = stablePoolNoPauseFactory.create(
            supportsDonation ? "Pool With Donation" : "Pool Without Donation",
            supportsDonation ? "PwD" : "PwoD",
            vault.buildTokenConfig(tokens),
            DEFAULT_AMP_FACTOR,
            roleAccounts,
            MAX_SWAP_FEE_PERCENTAGE,
            address(0),
            supportsDonation,
            false, // Do not disable unbalanced add/remove liquidity
            ZERO_BYTES32
        );

        // Initialize pool
        vm.prank(lp);
        router.initialize(stablePool, tokens, [poolInitAmount, poolInitAmount].toMemoryArray(), 0, false, bytes(""));

        return stablePool;
    }

    function _deployStablePoolWithPauseManager(address pauseManager) private returns (address) {
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.pauseManager = pauseManager;
        IERC20[] memory tokens = [address(dai), address(usdc)].toMemoryArray().asIERC20();

        // Using a unique salt per call so multiple pools can be deployed within the same test.
        bytes32 salt = keccak256(abi.encode("no-pause", pauseManager, block.timestamp, gasleft()));

        return
            stablePoolNoPauseFactory.create(
                "Stable Pool",
                "SP",
                vault.buildTokenConfig(tokens),
                DEFAULT_AMP_FACTOR,
                roleAccounts,
                MAX_SWAP_FEE_PERCENTAGE,
                address(0),
                false,
                false,
                salt
            );
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

    function _createHookTestLocals(address pool_) private view returns (HookTestLocals memory vars) {
        vars.bob.daiBefore = dai.balanceOf(bob);
        vars.bob.usdcBefore = usdc.balanceOf(bob);
        vars.bob.bptBefore = IERC20(pool_).balanceOf(bob);
        vars.vault.daiBefore = dai.balanceOf(address(vault));
        vars.vault.usdcBefore = usdc.balanceOf(address(vault));
        vars.poolBefore = vault.getRawBalances(pool_);
        vars.bptSupplyBefore = BalancerPoolToken(pool_).totalSupply();
    }

    function _fillAfterHookTestLocals(HookTestLocals memory vars, address pool_) private view {
        vars.bob.daiAfter = dai.balanceOf(bob);
        vars.bob.usdcAfter = usdc.balanceOf(bob);
        vars.bob.bptAfter = IERC20(pool_).balanceOf(bob);
        vars.vault.daiAfter = dai.balanceOf(address(vault));
        vars.vault.usdcAfter = usdc.balanceOf(address(vault));
        vars.poolAfter = vault.getRawBalances(pool_);
        vars.bptSupplyAfter = BalancerPoolToken(pool_).totalSupply();
    }
}
