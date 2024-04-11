// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { PoolHooks, TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { StablePoolWithHooksFactory } from "@balancer-labs/v3-pool-with-hooks/contracts/StablePoolWithHooksFactory.sol";
import { StablePoolWithHooks } from "@balancer-labs/v3-pool-with-hooks/contracts/StablePoolWithHooks.sol";
import { BaseHooks } from "@balancer-labs/v3-pool-with-hooks/contracts/BaseHooks.sol";
import { MockHooks } from "@balancer-labs/v3-pool-with-hooks/contracts/test/MockHooks.sol";
import { MockHooksWithParams } from "@balancer-labs/v3-pool-with-hooks/contracts/test/MockHooksWithParams.sol";
import { VaultMockDeployer } from "@balancer-labs/v3-vault/test/foundry/utils/VaultMockDeployer.sol";

import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

contract StablePoolWithHooksFactoryTest is BaseTest {
    using ArrayHelpers for *;

    IVaultMock internal vault;
    StablePoolWithHooksFactory internal poolFactory;

    string internal constant poolName = "Stable Pool With Hooks";
    string internal constant poolSymbol = "StablePoolWithHooks";

    address internal constant mockAddress = address(0);
    bytes internal constant mockBytes = bytes("");
    uint256 internal constant mockSwapFee = 1e16; // 1%
    uint256 internal constant mockAmpFactor = 200;

    TokenConfig[] internal tokenConfigs;
    IERC20[] internal erc20Tokens;
    bytes internal customHooksBytecode;
    bytes internal customHooksWithParamsBytecode;

    function setUp() public override {
        BaseTest.setUp();

        vault = IVaultMock(address(VaultMockDeployer.deploy()));
        poolFactory = new StablePoolWithHooksFactory(vault, 365 days);

        // Default creation parameters
        erc20Tokens.push(IERC20(dai));
        erc20Tokens.push(IERC20(usdc));
        TokenConfig[] memory tokenConfigsMemory = vault.buildTokenConfig(erc20Tokens);
        tokenConfigs.push(tokenConfigsMemory[0]);
        tokenConfigs.push(tokenConfigsMemory[1]);
        customHooksBytecode = type(MockHooks).creationCode;
        customHooksWithParamsBytecode = type(MockHooksWithParams).creationCode;
    }

    // POSITIVE TESTS

    function testCreate() public {
        bytes32 salt = bytes32("salt");

        (address poolAddress, address customHooksAddress) = poolFactory.create(
            poolName,
            poolSymbol,
            tokenConfigs,
            mockAmpFactor,
            mockSwapFee,
            salt,
            mockAddress,
            customHooksBytecode,
            mockBytes
        );

        assertEq(poolAddress, poolFactory.getDeploymentAddress(salt));
        assertEq(customHooksAddress, StablePoolWithHooks(poolAddress).hooksAddress());

        assertEq(BaseHooks(customHooksAddress).authorizedPool(), poolAddress);
        assertTrue(vault.isPoolRegistered(poolAddress));

        PoolHooks memory availableHooks = BaseHooks(customHooksAddress).availableHooks();
        assertTrue(availableHooks.shouldCallBeforeInitialize);
        assertTrue(availableHooks.shouldCallAfterInitialize);
        assertTrue(availableHooks.shouldCallBeforeAddLiquidity);
        assertTrue(availableHooks.shouldCallAfterAddLiquidity);
        assertTrue(availableHooks.shouldCallBeforeRemoveLiquidity);
        assertTrue(availableHooks.shouldCallAfterRemoveLiquidity);
        assertTrue(availableHooks.shouldCallBeforeSwap);
        assertTrue(availableHooks.shouldCallAfterSwap);
    }

    function testCreateWithParameters() public {
        bytes32 salt = bytes32("saltWithParameters");

        bool boolParameter = true;
        uint uintParameter = 123;
        address addressParameter = address(1);
        string memory stringParameter = "stringParameter";
        MockHooksWithParams.StructParameters memory structParameters = MockHooksWithParams.StructParameters({
            boolStructParameter: true,
            uintStructParameter: 123,
            addressStructParameter: address(1),
            stringStructParameter: "stringStructParameter"
        });
        bytes memory customHooksEncodedParams = abi.encode(
            boolParameter,
            uintParameter,
            addressParameter,
            stringParameter,
            structParameters
        );

        (, address customHooksAddress) = poolFactory.create(
            poolName,
            poolSymbol,
            tokenConfigs,
            mockAmpFactor,
            mockSwapFee,
            salt,
            mockAddress,
            customHooksWithParamsBytecode,
            customHooksEncodedParams
        );

        MockHooksWithParams customHooks = MockHooksWithParams(customHooksAddress);
        (
            bool boolStructParameter,
            uint uintStructParameter,
            address addressStructParameter,
            string memory stringStructParameter
        ) = customHooks.structParameters();

        assertEq(customHooks.boolParameter(), boolParameter);
        assertEq(customHooks.uintParameter(), uintParameter);
        assertEq(customHooks.addressParameter(), addressParameter);
        assertEq(customHooks.stringParameter(), stringParameter);
        assertEq(boolStructParameter, structParameters.boolStructParameter);
        assertEq(uintStructParameter, structParameters.uintStructParameter);
        assertEq(addressStructParameter, structParameters.addressStructParameter);
        assertEq(stringStructParameter, structParameters.stringStructParameter);
    }

    // NEGATIVE TESTS

    function testCreateMalformedHooks() public {
        bytes memory malformedHooks = new bytes(32);
        bytes32 malformedHooksSalt = bytes32("malformedHooks");

        vm.expectRevert("INITIALIZATION_FAILED");
        poolFactory.create(
            poolName,
            poolSymbol,
            tokenConfigs,
            mockAmpFactor,
            mockSwapFee,
            malformedHooksSalt,
            mockAddress,
            malformedHooks,
            mockBytes
        );
    }

    function testCreateSameSalt() public {
        bytes32 sameSalt = bytes32("sameSalt");

        poolFactory.create(
            poolName,
            poolSymbol,
            tokenConfigs,
            mockAmpFactor,
            mockSwapFee,
            sameSalt,
            mockAddress,
            customHooksBytecode,
            mockBytes
        );

        vm.expectRevert("DEPLOYMENT_FAILED");
        poolFactory.create(
            poolName,
            poolSymbol,
            tokenConfigs,
            mockAmpFactor,
            mockSwapFee,
            sameSalt,
            mockAddress,
            customHooksBytecode,
            mockBytes
        );
    }

    function testCreateWithIncorrectParameters() public {
        bytes32 incorrectParametersSalt = bytes32("incorrectParameters");

        vm.expectRevert("INITIALIZATION_FAILED");
        poolFactory.create(
            poolName,
            poolSymbol,
            tokenConfigs,
            mockAmpFactor,
            mockSwapFee,
            incorrectParametersSalt,
            mockAddress,
            customHooksWithParamsBytecode,
            mockBytes
        );
    }
}
