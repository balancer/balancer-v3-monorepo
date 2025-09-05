// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { IVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IVersion.sol";
import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";

import { ECLPSurgeHookDeployer } from "./utils/ECLPSurgeHookDeployer.sol";
import { ECLPSurgePoolFactoryDeployer } from "./utils/ECLPSurgePoolFactoryDeployer.sol";
import { ECLPSurgeHook } from "../../contracts/ECLPSurgeHook.sol";
import { ECLPSurgePoolFactory } from "../../contracts/ECLPSurgePoolFactory.sol";

contract ECLPSurgePoolFactoryTest is BaseVaultTest, ECLPSurgeHookDeployer, ECLPSurgePoolFactoryDeployer {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    string private constant FACTORY_VERSION = "Factory v1";
    string private constant POOL_VERSION = "Pool v1";

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    // Maximum swap fee of 10%
    uint64 public constant MAX_SWAP_FEE_PERCENTAGE = 10e16;

    ECLPSurgePoolFactory internal eclpPoolFactory;

    uint256 internal constant DEFAULT_AMP_FACTOR = 200;

    function setUp() public override {
        super.setUp();

        ECLPSurgeHook eclpSurgeHook = deployECLPSurgeHook(
            vault,
            DEFAULT_MAX_SURGE_FEE_PERCENTAGE,
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE,
            "Test"
        );

        eclpPoolFactory = deployECLPSurgePoolFactory(address(eclpSurgeHook), 365 days, FACTORY_VERSION, POOL_VERSION);
        vm.label(address(eclpPoolFactory), "eclp pool factory");

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function testFactoryHasHook() public {
        address surgeHook = address(eclpPoolFactory.getECLPSurgeHook());
        assertNotEq(surgeHook, address(0), "No surge hook deployed");

        address eclpPool = _deployAndInitializeECLPPool(false);
        HooksConfig memory config = vault.getHooksConfig(eclpPool);

        assertEq(config.hooksContract, surgeHook, "Hook contract mismatch");
    }

    function testVersions() public {
        address eclpPool = _deployAndInitializeECLPPool(false);

        assertEq(IVersion(eclpPoolFactory).version(), FACTORY_VERSION, "Wrong factory version");
        assertEq(eclpPoolFactory.getPoolVersion(), POOL_VERSION, "Wrong pool version in factory");
        assertEq(IVersion(eclpPool).version(), POOL_VERSION, "Wrong pool version in pool");
    }

    function testFactoryRegistration() public {
        address eclpPool = _deployAndInitializeECLPPool(false);

        assertEq(eclpPoolFactory.getPoolCount(), 1, "Wrong pool count");
        assertEq(eclpPoolFactory.getPools()[0], address(eclpPool), "Wrong pool");
    }

    function testFactoryPausedState() public view {
        uint32 pauseWindowDuration = eclpPoolFactory.getPauseWindowDuration();
        assertEq(pauseWindowDuration, 365 days);
    }

    function testFactoryNoPoolCreator() public {
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = alice;
        IERC20[] memory tokens = [address(dai), address(usdc)].toMemoryArray().asIERC20();

        (
            IGyroECLPPool.EclpParams memory eclpParams,
            IGyroECLPPool.DerivedEclpParams memory derivedEclpParams
        ) = getECLPPoolParams();

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(tokens);

        vm.expectRevert(BasePoolFactory.StandardPoolWithCreator.selector);
        eclpPoolFactory.create(
            "Pool Without Donation",
            "PwoD",
            tokenConfig,
            eclpParams,
            derivedEclpParams,
            roleAccounts,
            MAX_SWAP_FEE_PERCENTAGE,
            false,
            false,
            ZERO_BYTES32
        );
    }

    function testCreatePoolWithoutDonation() public {
        address eclpPool = _deployAndInitializeECLPPool(false);

        // Try to donate but fails because pool does not support donations
        vm.prank(bob);
        vm.expectRevert(IVaultErrors.DoesNotSupportDonation.selector);
        router.donate(eclpPool, [poolInitAmount, poolInitAmount].toMemoryArray(), false, bytes(""));
    }

    function testCreatePoolWithDonation() public {
        // Small amount, so the liquidity operation does not surge.
        uint256 amountToDonate = 10e18;

        address eclpPool = _deployAndInitializeECLPPool(true);

        HookTestLocals memory vars = _createHookTestLocals(eclpPool);

        // Donates to pool successfully
        vm.prank(bob);
        router.donate(eclpPool, [amountToDonate, amountToDonate].toMemoryArray(), false, bytes(""));

        _fillAfterHookTestLocals(vars, eclpPool);

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

        (
            IGyroECLPPool.EclpParams memory eclpParams,
            IGyroECLPPool.DerivedEclpParams memory derivedEclpParams
        ) = getECLPPoolParams();

        vm.expectRevert(IVaultErrors.MaxTokens.selector);
        eclpPoolFactory.create(
            "Big Pool",
            "TOO_BIG",
            tokenConfig,
            eclpParams,
            derivedEclpParams,
            roleAccounts,
            MAX_SWAP_FEE_PERCENTAGE,
            false,
            false,
            ZERO_BYTES32
        );
    }

    function _deployAndInitializeECLPPool(bool supportsDonation) private returns (address) {
        PoolRoleAccounts memory roleAccounts;
        IERC20[] memory tokens = [address(dai), address(usdc)].toMemoryArray().asIERC20();

        (
            IGyroECLPPool.EclpParams memory eclpParams,
            IGyroECLPPool.DerivedEclpParams memory derivedEclpParams
        ) = getECLPPoolParams();

        address eclpPool = eclpPoolFactory.create(
            supportsDonation ? "Pool With Donation" : "Pool Without Donation",
            supportsDonation ? "PwD" : "PwoD",
            vault.buildTokenConfig(tokens),
            eclpParams,
            derivedEclpParams,
            roleAccounts,
            MAX_SWAP_FEE_PERCENTAGE,
            supportsDonation,
            false,
            ZERO_BYTES32
        );

        // Initialize pool
        vm.prank(lp);
        router.initialize(eclpPool, tokens, [poolInitAmount, poolInitAmount].toMemoryArray(), 0, false, bytes(""));

        return eclpPool;
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
