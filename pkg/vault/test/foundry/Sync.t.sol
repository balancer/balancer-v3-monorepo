// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IERC20MultiToken } from "@balancer-labs/v3-interfaces/contracts/vault/IERC20MultiToken.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { Router } from "../../contracts/Router.sol";
import { RouterCommon } from "../../contracts/RouterCommon.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";
import { VaultExtensionMock } from "../../contracts/test/VaultExtensionMock.sol";

import { VaultMockDeployer } from "./utils/VaultMockDeployer.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {
    AddLiquidityKind,
    RemoveLiquidityKind,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

contract SyncTest is BaseVaultTest {
    using ArrayHelpers for *;

    ERC4626TestToken internal waDAI;
    ERC4626TestToken internal waUSDC;

    uint256 internal waDaiIdx;
    uint256 internal waUsdcIdx;

    address internal boostedPool;

    // The boosted pool will have 100x the liquidity of the buffer
    uint256 internal boostedPoolAmount = 10e6 * 1e18;
    uint256 internal bufferAmount = boostedPoolAmount / 100;
    uint256 internal tooLargeSwapAmount = boostedPoolAmount / 2;
    // We will swap with 10% of the buffer
    uint256 internal swapAmount = bufferAmount / 10;
    // LP can unbalance buffer with this amount
    uint256 internal unbalanceDelta = bufferAmount / 2;



    uint256[] internal amountsIn = [poolInitAmount, poolInitAmount].toMemoryArray();

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        waDAI = new ERC4626TestToken(dai, "Wrapped aDAI", "waDAI", 18);
        vm.label(address(waDAI), "waDAI");

        // "USDC" is deliberately 18 decimals to test one thing at a time.
        waUSDC = new ERC4626TestToken(usdc, "Wrapped aUSDC", "waUSDC", 18);
        vm.label(address(waUSDC), "waUSDC");

        (waDaiIdx, waUsdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));

        _initializeBuffers();
        _initializeBoostedPool();

        authorizer.grantRole(
            0x78823457cc024a2de284a4154c07b727e52277748dbc1ef973c8ee254462a230,
            address(router)
        );
        // Test Dos attack with 1 wei, related: https://github.com/balancer/balancer-v3-monorepo/issues/580
        // TODO: Buffer tests

        // Token in always dai
        deal(address(dai), address(this), 1, false);
        dai.transfer(address(vault), 1);

        // Token out always usdc
        deal(address(usdc), address(this), 1, false);
        usdc.transfer(address(usdc), 1);

        deal(address(waDAI), address(this), 1, false);
        waDAI.transfer(address(vault), 1);

        deal(address(waUSDC), address(this), 1, false);
        waUSDC.transfer(address(vault), 1);
    }

    /*
      Router
    */
    function testAddLiquidityProportionalDos() public {
        vm.prank(alice);

        router.addLiquidityProportional(pool, amountsIn, amountsIn[0], false, bytes(""));
    }

    function testAddLiquidityUnbalanced() public {
        vm.prank(alice);

        router.addLiquidityUnbalanced(pool, amountsIn, amountsIn[0], false, bytes(""));
    }

    function testAddLiquiditySingleTokenExactOut() public {
        vm.prank(alice);

        router.addLiquiditySingleTokenExactOut(pool, dai, amountsIn[0], amountsIn[0], false, bytes(""));
    }

    function testAddLiquidityCustomDos() public {
        vm.prank(alice);

        router.addLiquidityCustom(pool, amountsIn, amountsIn[0], false, bytes(""));
    }

    // addLiquidityHook?

    // Minimum error, need to work on bptAmountIn
    function testRemoveLiquidityProportionalDos() public {
        _addLiquidity();

        vm.prank(alice);

        router.removeLiquidityProportional(pool, (amountsIn[0] + 1) * 2, amountsIn, false, bytes(""));
    }

    function testRemoveLiquiditySingleTokenExactInDos() public {
        _addLiquidity();

        vm.prank(alice);

        router.removeLiquiditySingleTokenExactIn(pool, amountsIn[0], usdc, 1, false, bytes(""));
    }

    function testRemoveLiquiditySingleTokenExactOut() public {
        _addLiquidity();

        vm.prank(alice);

        router.removeLiquiditySingleTokenExactOut(pool, amountsIn[0], usdc, 1, false, bytes(""));
    }

    function testRemoveLiquidityCustomDos() public {
        _addLiquidity();

        vm.prank(alice);

        router.removeLiquidityCustom(pool, amountsIn[0], amountsIn, false, bytes(""));
    }

    function testRemoveLiquidityRecoveryDos() public {
        authorizer.grantRole(vault.getActionId(IVaultAdmin.enableRecoveryMode.selector), admin);

        vm.prank(admin);
        vault.enableRecoveryMode(pool);

        _addLiquidity();

        vm.prank(alice);

        router.removeLiquidityRecovery(pool, amountsIn[0]);
    }

    function testSwapSingleTokenExactIn() public {
        _addLiquidity();

        vm.prank(bob);
        router.swapSingleTokenExactIn(pool, dai, usdc, amountsIn[0], amountsIn[0], block.timestamp, false, bytes(""));
    }

    function testSwapSingleTokenExactOut() public {
        _addLiquidity();

        vm.prank(bob);
        router.swapSingleTokenExactOut(pool, dai, usdc, amountsIn[0], amountsIn[0], block.timestamp, false, bytes(""));
    }

    function testAddLiquidityToBuffer() public {
        vm.prank(lp);
        router.addLiquidityToBuffer(
            IERC4626(waDAI),
            amountsIn[0],
            amountsIn[0],
            address(lp)
        );
    }

    function testRemoveLiquidityFromBuffer() public {
        _addLiquidityToBuffer();

        vm.prank(lp);
        router.removeLiquidityFromBuffer(
            IERC4626(waDAI),
            amountsIn[0]
        );
    }

    function _initializeBuffers() internal {
        // Create and fund buffer pools
        vm.startPrank(lp);
        dai.mint(address(lp), 2 * bufferAmount);
        dai.approve(address(waDAI), 2 * bufferAmount);
        waDAI.deposit(2 * bufferAmount, address(lp));

        usdc.mint(address(lp), 2 * bufferAmount);
        usdc.approve(address(waUSDC), 2 * bufferAmount);
        waUSDC.deposit(2 * bufferAmount, address(lp));
        vm.stopPrank();

        vm.startPrank(lp);
        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);
        waUSDC.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waUSDC), address(batchRouter), type(uint160).max, type(uint48).max);

        router.addLiquidityToBuffer(waDAI, bufferAmount, bufferAmount, address(lp));
        router.addLiquidityToBuffer(waUSDC, bufferAmount, bufferAmount, address(lp));
        vm.stopPrank();
    }

    function _initializeBoostedPool() internal {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[waDaiIdx].token = IERC20(waDAI);
        tokenConfig[waUsdcIdx].token = IERC20(waUSDC);
        tokenConfig[0].tokenType = TokenType.WITH_RATE;
        tokenConfig[1].tokenType = TokenType.WITH_RATE;
        tokenConfig[waDaiIdx].rateProvider = IRateProvider(address(waDAI));
        tokenConfig[waUsdcIdx].rateProvider = IRateProvider(address(waUSDC));

        PoolMock newPool = new PoolMock(IVault(address(vault)), "Boosted Pool", "BOOSTYBOI");

        factoryMock.registerTestPool(address(newPool), tokenConfig, poolHooksContract);

        vm.label(address(newPool), "boosted pool");
        boostedPool = address(newPool);

        vm.startPrank(bob);
        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);
        waUSDC.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waUSDC), address(batchRouter), type(uint160).max, type(uint48).max);

        dai.mint(address(bob), boostedPoolAmount);
        dai.approve(address(waDAI), boostedPoolAmount);
        waDAI.deposit(boostedPoolAmount, address(bob));

        usdc.mint(address(bob), boostedPoolAmount);
        usdc.approve(address(waUSDC), boostedPoolAmount);
        waUSDC.deposit(boostedPoolAmount, address(bob));

        _initPool(boostedPool, [boostedPoolAmount, boostedPoolAmount].toMemoryArray(), boostedPoolAmount * 2 - MIN_BPT);
        vm.stopPrank();
    }

    function _addLiquidity() internal {
        vm.prank(alice);

        router.addLiquidityProportional(pool, amountsIn, amountsIn[0], false, bytes(""));

        deal(address(dai), address(this), 1, false);
        dai.transfer(address(vault), 1);

        // Token out always usdc
        deal(address(usdc), address(this), 1, false);
        usdc.transfer(address(usdc), 1);

        deal(address(waDAI), address(this), 1, false);
        waDAI.transfer(address(vault), 1);

        deal(address(waUSDC), address(this), 1, false);
        waUSDC.transfer(address(vault), 1);
    }

    function _addLiquidityToBuffer() internal {
        vm.prank(lp);
        router.addLiquidityToBuffer(
            IERC4626(waDAI),
            amountsIn[0],
            amountsIn[0],
            address(lp)
        ); 

        deal(address(dai), address(this), 1, false);
        dai.transfer(address(vault), 1);

        // Token out always usdc
        deal(address(usdc), address(this), 1, false);
        usdc.transfer(address(usdc), 1);

        deal(address(waDAI), address(this), 1, false);
        waDAI.transfer(address(vault), 1);

        deal(address(waUSDC), address(this), 1, false);
        waUSDC.transfer(address(vault), 1);
    }
}
