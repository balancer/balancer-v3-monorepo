// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import {
    AddLiquidityKind,
    RemoveLiquidityKind,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { StablePoolWithHooksFactory } from "@balancer-labs/v3-pool-with-hooks/contracts/StablePoolWithHooksFactory.sol";
import { StablePoolWithHooks } from "@balancer-labs/v3-pool-with-hooks/contracts/StablePoolWithHooks.sol";
import { BaseHooks } from "@balancer-labs/v3-pool-with-hooks/contracts/BaseHooks.sol";
import { MockHooks } from "@balancer-labs/v3-pool-with-hooks/contracts/test/MockHooks.sol";
import { RouterMock } from "@balancer-labs/v3-vault/contracts/test/RouterMock.sol";
import { VaultMockDeployer } from "@balancer-labs/v3-vault/test/foundry/utils/VaultMockDeployer.sol";
import { DeployPermit2 } from "permit2/test/utils/DeployPermit2.sol";

import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";

contract StablePoolWithHooksTest is BaseTest, DeployPermit2 {
    using ArrayHelpers for *;

    IPermit2 internal permit2;
    IVaultMock internal vault;
    RouterMock internal router;
    StablePoolWithHooksFactory internal poolFactory;
    StablePoolWithHooks internal pool;
    BaseHooks internal customHooks;

    string internal constant poolName = "Stable Pool With Hooks";
    string internal constant poolSymbol = "StablePoolWithHooks";
    uint256 internal constant mockSwapFee = 1e16; // 1%
    uint256 internal constant mockAmpFactor = 200;

    TokenConfig[] internal tokenConfigs;
    IERC20[] internal erc20Tokens;
    bytes internal customHooksBytecode;

    // Mock parameters
    uint256[] internal mockUint256Array = new uint256[](1);
    bytes internal mockBytes = bytes("");
    uint256 internal mockUint256 = 0;
    address internal mockAddress = address(0);
    IBasePool.PoolSwapParams internal mockSwapParams =
        IBasePool.PoolSwapParams(SwapKind.EXACT_IN, 0, mockUint256Array, 0, 0, mockAddress, mockBytes);
    IPoolHooks.AfterSwapParams internal mockAfterSwapParams =
        IPoolHooks.AfterSwapParams(SwapKind.EXACT_IN, IERC20(dai), IERC20(usdc), 0, 0, 0, 0, mockAddress, mockBytes);

    function setUp() public override {
        BaseTest.setUp();

        permit2 = IPermit2(deployPermit2());
        vault = IVaultMock(address(VaultMockDeployer.deploy()));
        poolFactory = new StablePoolWithHooksFactory(vault, 365 days);
        router = new RouterMock(IVault(address(vault)), weth, permit2);

        // Default creation parameters
        erc20Tokens.push(IERC20(dai));
        erc20Tokens.push(IERC20(usdc));
        TokenConfig[] memory tokenConfigsMemory = vault.buildTokenConfig(erc20Tokens);
        tokenConfigs.push(tokenConfigsMemory[0]);
        tokenConfigs.push(tokenConfigsMemory[1]);
        customHooksBytecode = type(MockHooks).creationCode;

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

        pool = StablePoolWithHooks(poolAddress);
        customHooks = BaseHooks(customHooksAddress);
    }

    // POSITIVE TESTS

    function testAuthorizedPoolCalls() public {
        vm.startPrank(address(vault));

        vm.expectEmit(false, false, false, true, address(customHooks));
        emit MockHooks.HookCalled("onBeforeInitialize");
        pool.onBeforeInitialize(mockUint256Array, mockBytes);

        vm.expectEmit(false, false, false, true, address(customHooks));
        emit MockHooks.HookCalled("onAfterInitialize");
        pool.onAfterInitialize(mockUint256Array, mockUint256, mockBytes);

        vm.expectEmit(false, false, false, true, address(customHooks));
        emit MockHooks.HookCalled("onBeforeAddLiquidity");
        pool.onBeforeAddLiquidity(
            mockAddress,
            AddLiquidityKind.UNBALANCED,
            mockUint256Array,
            mockUint256,
            mockUint256Array,
            mockBytes
        );

        vm.expectEmit(false, false, false, true, address(customHooks));
        emit MockHooks.HookCalled("onAfterAddLiquidity");
        pool.onAfterAddLiquidity(mockAddress, mockUint256Array, mockUint256, mockUint256Array, mockBytes);

        vm.expectEmit(false, false, false, true, address(customHooks));
        emit MockHooks.HookCalled("onBeforeRemoveLiquidity");
        pool.onBeforeRemoveLiquidity(
            mockAddress,
            RemoveLiquidityKind.CUSTOM,
            mockUint256,
            mockUint256Array,
            mockUint256Array,
            mockBytes
        );

        vm.expectEmit(false, false, false, true, address(customHooks));
        emit MockHooks.HookCalled("onAfterRemoveLiquidity");
        pool.onAfterRemoveLiquidity(mockAddress, mockUint256, mockUint256Array, mockUint256Array, mockBytes);

        vm.expectEmit(false, false, false, true, address(customHooks));
        emit MockHooks.HookCalled("onBeforeSwap");
        pool.onBeforeSwap(mockSwapParams);

        vm.expectEmit(false, false, false, true, address(customHooks));
        emit MockHooks.HookCalled("onAfterSwap");
        pool.onAfterSwap(mockAfterSwapParams, mockUint256);

        vm.stopPrank();
    }

    // NEGATIVE TESTS

    function testUnauthorizedHooksCalls() public {
        bytes32 salt = bytes32("unauthorizedPool");
        address unauthorizedPoolAddress = poolFactory.getDeploymentAddress(salt);
        bytes memory revertReason = abi.encodeWithSelector(BaseHooks.SenderIsNotPool.selector, unauthorizedPoolAddress);

        vm.startPrank(unauthorizedPoolAddress);

        vm.expectRevert(revertReason);
        customHooks.onBeforeInitialize(mockUint256Array, mockBytes);

        vm.expectRevert(revertReason);
        customHooks.onAfterInitialize(mockUint256Array, mockUint256, mockBytes);

        vm.expectRevert(revertReason);
        customHooks.onBeforeAddLiquidity(
            mockAddress,
            AddLiquidityKind.UNBALANCED,
            mockUint256Array,
            mockUint256,
            mockUint256Array,
            mockBytes
        );

        vm.expectRevert(revertReason);
        customHooks.onAfterAddLiquidity(mockAddress, mockUint256Array, mockUint256, mockUint256Array, mockBytes);

        vm.expectRevert(revertReason);
        customHooks.onBeforeRemoveLiquidity(
            mockAddress,
            RemoveLiquidityKind.CUSTOM,
            mockUint256,
            mockUint256Array,
            mockUint256Array,
            mockBytes
        );

        vm.expectRevert(revertReason);
        customHooks.onAfterRemoveLiquidity(mockAddress, mockUint256, mockUint256Array, mockUint256Array, mockBytes);

        vm.expectRevert(revertReason);
        customHooks.onBeforeSwap(mockSwapParams);

        vm.expectRevert(revertReason);
        customHooks.onAfterSwap(mockAfterSwapParams, mockUint256);

        vm.stopPrank();
    }

    function testUnauthorizedPoolCalls() public {
        bytes32 salt = bytes32("unauthorizedVault");
        address unauthorizedVault = CREATE3.getDeployed(salt);
        bytes memory revertReason = abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, unauthorizedVault);

        vm.startPrank(unauthorizedVault);

        vm.expectRevert(revertReason);
        pool.onBeforeInitialize(mockUint256Array, mockBytes);

        vm.expectRevert(revertReason);
        pool.onAfterInitialize(mockUint256Array, mockUint256, mockBytes);

        vm.expectRevert(revertReason);
        pool.onBeforeAddLiquidity(
            mockAddress,
            AddLiquidityKind.UNBALANCED,
            mockUint256Array,
            mockUint256,
            mockUint256Array,
            mockBytes
        );

        vm.expectRevert(revertReason);
        pool.onAfterAddLiquidity(mockAddress, mockUint256Array, mockUint256, mockUint256Array, mockBytes);

        vm.expectRevert(revertReason);
        pool.onBeforeRemoveLiquidity(
            mockAddress,
            RemoveLiquidityKind.CUSTOM,
            mockUint256,
            mockUint256Array,
            mockUint256Array,
            mockBytes
        );

        vm.expectRevert(revertReason);
        pool.onAfterRemoveLiquidity(mockAddress, mockUint256, mockUint256Array, mockUint256Array, mockBytes);

        vm.expectRevert(revertReason);
        pool.onBeforeSwap(mockSwapParams);

        vm.expectRevert(revertReason);
        pool.onAfterSwap(mockAfterSwapParams, mockUint256);

        vm.stopPrank();
    }
}
