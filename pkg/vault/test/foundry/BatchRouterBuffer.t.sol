// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TokenConfig, TokenType, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { RouterCommon } from "../../contracts/RouterCommon.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BatchRouterBufferTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 internal bufferInitialAmount = 1e5 * 1e18;
    uint256 internal boostedPoolInitialAmount = 10e6 * 1e18;
    uint256 internal boostedPoolInitialBPTAmount = boostedPoolInitialAmount * 2;

    ERC4626TestToken internal waDAI;
    ERC4626TestToken internal waUSDC;
    address internal boostedPool;

    uint256 internal waDaiIdx;
    uint256 internal waUsdcIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        waDAI = new ERC4626TestToken(dai, "Wrapped aDAI", "waDAI", 18);
        vm.label(address(waDAI), "waDAI");

        // "USDC" is deliberately 18 decimals to test one thing at a time.
        waUSDC = new ERC4626TestToken(usdc, "Wrapped aUSDC", "waUSDC", 18);
        vm.label(address(waUSDC), "waUSDC");

        (waDaiIdx, waUsdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));

        initializeBuffers();
        initializeBoostedPool();
    }

    function initializeBuffers() private {
        // Create and fund buffer pools
        vm.startPrank(lp);
        dai.mint(lp, 2 * bufferInitialAmount);
        dai.approve(address(waDAI), 2 * bufferInitialAmount);
        waDAI.deposit(2 * bufferInitialAmount, lp);

        usdc.mint(lp, 2 * bufferInitialAmount);
        usdc.approve(address(waUSDC), 2 * bufferInitialAmount);
        waUSDC.deposit(2 * bufferInitialAmount, lp);
        vm.stopPrank();

        vm.startPrank(lp);
        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);
        waUSDC.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waUSDC), address(batchRouter), type(uint160).max, type(uint48).max);

        router.addLiquidityToBuffer(waDAI, bufferInitialAmount, bufferInitialAmount, lp);
        router.addLiquidityToBuffer(waUSDC, bufferInitialAmount, bufferInitialAmount, lp);
        vm.stopPrank();
    }

    function initializeBoostedPool() private {
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
        waUSDC.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);

        dai.mint(bob, boostedPoolInitialAmount);
        dai.approve(address(waDAI), boostedPoolInitialAmount);
        waDAI.deposit(boostedPoolInitialAmount, bob);

        usdc.mint(bob, boostedPoolInitialAmount);
        usdc.approve(address(waUSDC), boostedPoolInitialAmount);
        waUSDC.deposit(boostedPoolInitialAmount, bob);

        _initPool(
            boostedPool,
            [boostedPoolInitialAmount, boostedPoolInitialAmount].toMemoryArray(),
            boostedPoolInitialBPTAmount - MIN_BPT
        );
        vm.stopPrank();
    }

    function testAddLiquidationBuffer() public {
        uint256 amount = bufferInitialAmount / 2;
        uint256[] memory exactUnderlyingAmountsIn = [amount, amount].toMemoryArray();

        _prankStaticCall();
        uint256 expectBPTOut = router.queryAddLiquidityUnbalanced(boostedPool, exactUnderlyingAmountsIn, new bytes(0));

        vm.startPrank(alice);

        uint256 beforeUSDCBalance = usdc.balanceOf(address(alice));
        uint256 beforeDAIBalance = dai.balanceOf(address(alice));
        (uint256 beforeWaUSDCBufferBalanceUnderling, uint256 beforeWaUSDCBufferBalanceWrapped) = vault.getBufferBalance(
            waUSDC
        );
        (uint256 beforeWaDAIBufferBalanceUnderling, uint256 beforeWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
            waDAI
        );

        uint256 bptOut = batchRouter.addLiquidityUnbalancedToBoostedPool(
            boostedPool,
            exactUnderlyingAmountsIn,
            1,
            false,
            new bytes(0)
        );

        {
            uint256 afterUSDCBalance = usdc.balanceOf(address(alice));
            assertEq(beforeUSDCBalance - afterUSDCBalance, amount, "USDC balance should decrease");
        }
        {
            uint256 afterDAIBalance = dai.balanceOf(address(alice));
            assertEq(beforeDAIBalance - afterDAIBalance, amount, "DAI balance should decrease");
        }
        {
            (uint256 afterWaUSDCBufferBalanceUnderling, uint256 afterWaUSDCBufferBalanceWrapped) = vault
                .getBufferBalance(waUSDC);
            assertEq(
                beforeWaUSDCBufferBalanceWrapped - afterWaUSDCBufferBalanceWrapped,
                amount,
                "waUSDC wrapped buffer balance should decrease"
            );
            assertEq(
                afterWaUSDCBufferBalanceUnderling - beforeWaUSDCBufferBalanceUnderling,
                amount,
                "waUSDC underlying buffer balance should increase"
            );
        }
        {
            (uint256 afterWaDAIBufferBalanceUnderling, uint256 afterWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
                waDAI
            );
            assertEq(
                beforeWaDAIBufferBalanceWrapped - afterWaDAIBufferBalanceWrapped,
                amount,
                "waDAI wrapped buffer balance should decrease"
            );
            assertEq(
                afterWaDAIBufferBalanceUnderling - beforeWaDAIBufferBalanceUnderling,
                amount,
                "waDAI underlying buffer balance should increase"
            );
        }

        // console.log("expectBPTOut", expectBPTOut);
        // console.log("bptOut", bptOut);

        vm.stopPrank();
    }
}
