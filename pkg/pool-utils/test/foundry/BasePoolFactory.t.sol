// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    TokenConfig,
    PoolRoleAccounts,
    LiquidityManagement
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { BasePoolFactoryMock } from "../../contracts/test/BasePoolFactoryMock.sol";

contract BasePoolFactoryTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint32 private constant _DEFAULT_PAUSE_WINDOW = 365 days;

    BasePoolFactoryMock internal testFactory;

    function setUp() public override {
        BaseVaultTest.setUp();

        testFactory = new BasePoolFactoryMock(
            IVault(address(vault)),
            _DEFAULT_PAUSE_WINDOW,
            type(PoolMock).creationCode
        );
    }

    function testConstructor() public {
        bytes memory creationCode = type(PoolMock).creationCode;
        uint32 pauseWindowDuration = _DEFAULT_PAUSE_WINDOW;

        BasePoolFactoryMock newFactory = new BasePoolFactoryMock(
            IVault(address(vault)),
            pauseWindowDuration,
            creationCode
        );

        assertEq(newFactory.getPauseWindowDuration(), pauseWindowDuration, "pauseWindowDuration is wrong");
        assertEq(address(newFactory.getVault()), address(vault), "Vault is wrong");
    }

    function testDisableNoAuthentication() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        testFactory.disable();
    }

    function testDisable() public {
        authorizer.grantRole(testFactory.getActionId(IBasePoolFactory.disable.selector), admin);

        assertFalse(testFactory.isDisabled(), "Factory is disabled");

        vm.prank(admin);
        testFactory.disable();

        assertTrue(testFactory.isDisabled(), "Factory is enabled");
    }

    function testEnsureEnabled() public {
        authorizer.grantRole(testFactory.getActionId(IBasePoolFactory.disable.selector), admin);

        assertFalse(testFactory.isDisabled(), "Factory is disabled");
        // Should pass, since the factory is enabled.
        testFactory.manualEnsureEnabled();

        vm.prank(admin);
        testFactory.disable();

        // Should revert, since the factory is disabled.
        vm.expectRevert(IBasePoolFactory.Disabled.selector);
        testFactory.manualEnsureEnabled();
    }

    function testRegisterPoolWithFactoryDisabled() public {
        // Disable the factory.
        authorizer.grantRole(testFactory.getActionId(IBasePoolFactory.disable.selector), admin);
        vm.prank(admin);
        testFactory.disable();

        address newPool = address(deployPoolMock(IVault(address(vault)), "Test Pool", "TEST"));
        vm.expectRevert(IBasePoolFactory.Disabled.selector);
        testFactory.manualRegisterPoolWithFactory(newPool);
    }

    function testRegisterPoolWithFactory() public {
        address newPool = address(deployPoolMock(IVault(address(vault)), "Test Pool", "TEST"));

        assertFalse(testFactory.isPoolFromFactory(newPool), "Pool is already registered with factory");

        testFactory.manualRegisterPoolWithFactory(newPool);

        assertTrue(testFactory.isPoolFromFactory(newPool), "Pool is not registered with factory");
        assertEq(testFactory.getPoolsInRange(0, 1)[0], newPool, "Pools list does not contain the new pool");
        assertEq(testFactory.getPoolCount(), 1, "Wrong pool count");
    }

    function testGetPoolsOutOfRange() public {
        uint256 count = 30;
        _registerPools(count);

        vm.expectRevert(IBasePoolFactory.IndexOutOfBounds.selector);
        testFactory.getPoolsInRange(count, 1);
    }

    function testGetPoolsFullList() public {
        uint256 count = 30;
        address[] memory poolsDeployed = _registerPools(count);
        address[] memory poolsReturned = testFactory.getPools();

        assertEq(poolsReturned.length, count, "Wrong number of pools returned");

        _compareArrays(poolsDeployed, poolsReturned);
    }

    function testRegisterMultiplePools() public {
        uint256 count = 30;
        address[] memory pools = _registerPools(count);

        assertEq(testFactory.getPoolCount(), count, "Wrong pool count");

        _compareArrays(testFactory.getPoolsInRange(0, count), pools);
        _compareArrays(testFactory.getPoolsInRange(0, 100000), pools);
        for (uint256 i = 0; i < count; i++) {
            assertEq(testFactory.getPoolsInRange(i, 1)[0], pools[i], "Pools list does not contain the new pool");
        }

        address[] memory firstHalf = testFactory.getPoolsInRange(0, count / 2);
        address[] memory secondHalf = testFactory.getPoolsInRange(count / 2, count);

        for (uint256 i = 0; i < count; i++) {
            if (i < count / 2) {
                assertEq(firstHalf[i], pools[i], "First half does not contain the new pool");
            } else {
                assertEq(secondHalf[i - count / 2], pools[i], "Second half does not contain the new pool");
            }
        }
    }

    function _registerPools(uint256 count) private returns (address[] memory pools) {
        pools = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            pools[i] = address(deployPoolMock(IVault(address(vault)), "Test Pool", "TEST"));
            testFactory.manualRegisterPoolWithFactory(pools[i]);
            assertTrue(testFactory.isPoolFromFactory(pools[i]), "Pool is not registered with factory");
        }
    }

    function testRegisterPoolWithVault() public {
        address newPool = address(deployPoolMock(IVault(address(vault)), "Test Pool", "TEST"));
        TokenConfig[] memory newTokens = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );
        uint256 newSwapFeePercentage = 0;
        bool protocolFeeExempt = false;
        PoolRoleAccounts memory roleAccounts;
        address hooksContract = address(0);
        LiquidityManagement memory liquidityManagement;

        assertFalse(vault.isPoolRegistered(newPool), "Pool is already registered with vault");

        testFactory.manualRegisterPoolWithVault(
            newPool,
            newTokens,
            newSwapFeePercentage,
            protocolFeeExempt,
            roleAccounts,
            hooksContract,
            liquidityManagement
        );

        assertTrue(vault.isPoolRegistered(newPool), "Pool is not registered with vault");
    }

    function testCreate() public {
        string memory name = "Test Pool Create";
        string memory symbol = "TEST_CREATE";
        address newPool = testFactory.manualCreate(name, symbol, ZERO_BYTES32);

        assertEq(PoolMock(newPool).name(), name, "Pool name is wrong");
        assertEq(PoolMock(newPool).symbol(), symbol, "Pool symbol is wrong");
        assertTrue(testFactory.isPoolFromFactory(newPool), "Pool is not registered with factory");
    }

    function testGetDeploymentAddress() public {
        string memory name = "Test Deployment Address";
        string memory symbol = "DEPLOYMENT_ADDRESS";
        bytes32 salt = keccak256(abi.encode("abc"));

        bytes memory poolArgs = abi.encode(vault, name, symbol);

        address predictedAddress = testFactory.getDeploymentAddress(poolArguments, salt);
        address newPool = testFactory.manualCreate(name, symbol, salt);
        assertEq(newPool, predictedAddress, "predictedAddress is wrong");

        vm.prank(bob);
        address bobAddress = testFactory.getDeploymentAddress(poolArguments, salt);
        assertNotEq(bobAddress, predictedAddress, "Different sender generates the same address");

        vm.chainId(10000);
        address chainAddress = testFactory.getDeploymentAddress(poolArguments, salt);
        assertNotEq(chainAddress, predictedAddress, "Different chain generates the same address");
    }

    function testGetDefaultPoolHooksContract() public view {
        assertEq(testFactory.getDefaultPoolHooksContract(), address(0), "Wrong hooks contract");
    }

    function testGetDefaultLiquidityManagement() public view {
        LiquidityManagement memory liquidityManagement = testFactory.getDefaultLiquidityManagement();

        assertFalse(liquidityManagement.enableDonation, "enableDonation is true");
        assertFalse(liquidityManagement.disableUnbalancedLiquidity, "disableUnbalancedLiquidity is true");
        assertFalse(liquidityManagement.enableAddLiquidityCustom, "enableAddLiquidityCustom is true");
        assertFalse(liquidityManagement.enableRemoveLiquidityCustom, "enableRemoveLiquidityCustom is true");
    }

    function _compareArrays(address[] memory a, address[] memory b) internal pure {
        assertEq(a.length, b.length, "Arrays have different lengths");
        for (uint256 i = 0; i < a.length; i++) {
            assertEq(a[i], b[i], "Arrays have different elements");
        }
    }
}
