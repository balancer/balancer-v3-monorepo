// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TokenConfig, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { PoolMock } from "../../../contracts/test/PoolMock.sol";
import { BaseVaultTest } from "./BaseVaultTest.sol";

abstract contract BaseERC4626BufferTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 bufferInitialAmount = 1e5 * 1e18;
    uint256 initialLPBufferAmount = 1e5 * 1e18;
    uint256 erc4626PoolInitialAmount = 10e6 * 1e18;
    uint256 erc4626PoolInitialBPTAmount = erc4626PoolInitialAmount * 2;

    ERC4626TestToken internal waDAI;
    ERC4626TestToken internal waUSDC;
    uint256 internal waDaiIdx;
    uint256 internal waUsdcIdx;
    address erc4626Pool;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _setupWrappedTokens();

        _initializeBuffers();
        _initializeERC4626Pool();
    }

    function _initializeBuffers() private {
        // Create and fund buffer pools.
        vm.startPrank(lp);
        dai.mint(lp, initialLPBufferAmount);
        dai.approve(address(waDAI), initialLPBufferAmount);
        uint256 waDAILPShares = waDAI.deposit(initialLPBufferAmount, lp);
        console.log("waDAILPShares", waDAILPShares);

        usdc.mint(lp, initialLPBufferAmount);
        usdc.approve(address(waUSDC), initialLPBufferAmount);
        uint256 waUSDCLPShares = waUSDC.deposit(initialLPBufferAmount, lp);
        console.log("waUSDCLPShares", waUSDCLPShares);
        vm.stopPrank();

        vm.startPrank(lp);
        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);
        waUSDC.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waUSDC), address(batchRouter), type(uint160).max, type(uint48).max);

        router.addLiquidityToBuffer(waDAI, bufferInitialAmount, waDAILPShares, lp);
        router.addLiquidityToBuffer(waUSDC, bufferInitialAmount, waUSDCLPShares, lp);
        vm.stopPrank();
    }

    function _initializeERC4626Pool() private {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[waDaiIdx].token = IERC20(waDAI);
        tokenConfig[waUsdcIdx].token = IERC20(waUSDC);
        tokenConfig[0].tokenType = TokenType.WITH_RATE;
        tokenConfig[1].tokenType = TokenType.WITH_RATE;
        tokenConfig[waDaiIdx].rateProvider = IRateProvider(address(waDAI));
        tokenConfig[waUsdcIdx].rateProvider = IRateProvider(address(waUSDC));

        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC4626 Pool", "ERC4626P");

        factoryMock.registerTestPool(address(newPool), tokenConfig, poolHooksContract);

        vm.label(address(newPool), "erc4626 pool");
        erc4626Pool = address(newPool);

        vm.startPrank(bob);
        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);

        waUSDC.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waUSDC), address(batchRouter), type(uint160).max, type(uint48).max);

        dai.mint(bob, erc4626PoolInitialAmount);
        dai.approve(address(waDAI), erc4626PoolInitialAmount);
        uint256 waDaiBobShares = waDAI.deposit(erc4626PoolInitialAmount, bob);

        usdc.mint(bob, erc4626PoolInitialAmount);
        usdc.approve(address(waUSDC), erc4626PoolInitialAmount);
        uint256 waUsdcBobShares = waUSDC.deposit(erc4626PoolInitialAmount, bob);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[waDaiIdx] = waDaiBobShares;
        amountsIn[waUsdcIdx] = waUsdcBobShares;

        _initPool(erc4626Pool, amountsIn, erc4626PoolInitialBPTAmount - MIN_BPT);

        IERC20(address(erc4626Pool)).approve(address(permit2), MAX_UINT256);
        permit2.approve(address(erc4626Pool), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(erc4626Pool), address(batchRouter), type(uint160).max, type(uint48).max);

        IERC20(address(erc4626Pool)).approve(address(router), type(uint256).max);
        IERC20(address(erc4626Pool)).approve(address(batchRouter), type(uint256).max);
        vm.stopPrank();
    }

    function _setupWrappedTokens() private {
        waDAI = new ERC4626TestToken(dai, "Wrapped aDAI", "waDAI", 18);
        vm.label(address(waDAI), "waDAI");

        // "USDC" is deliberately 18 decimals to test one thing at a time.
        waUSDC = new ERC4626TestToken(usdc, "Wrapped aUSDC", "waUSDC", 18);
        vm.label(address(waUSDC), "waUSDC");

        (waDaiIdx, waUsdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));

        // Manipulate rates before creating the ERC4626 pools. It's important to don't have a 1:1 rate when testing
        // ERC4626 tokens, so we can differ what's wrapped and what's underlying amounts.
        dai.mint(lp, 10 * erc4626PoolInitialAmount);
        usdc.mint(lp, 10 * erc4626PoolInitialAmount);
        // Deposit sets the rate to 1.
        vm.startPrank(lp);
        dai.approve(address(waDAI), 10 * erc4626PoolInitialAmount);
        waDAI.deposit(10 * erc4626PoolInitialAmount, lp);
        usdc.approve(address(waUSDC), 10 * erc4626PoolInitialAmount);
        waUSDC.deposit(10 * erc4626PoolInitialAmount, lp);
        vm.stopPrank();
        // Changing asset balances without minting shares makes the balance be different than 1.
        dai.mint(address(waDAI), 2 * erc4626PoolInitialAmount);
        usdc.mint(address(waUSDC), 23 * erc4626PoolInitialAmount);
    }
}
