// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TokenConfig, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { ERC4626BufferPoolFactory } from "../../contracts/factories/ERC4626BufferPoolFactory.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BufferSwapTest is BaseVaultTest {
    using ArrayHelpers for *;

    ERC4626TestToken internal waDAI;
    ERC4626TestToken internal waUSDC;

    ERC4626BufferPoolFactory bufferFactory;

    // For two-token pools with waDAI/waUSDC, keep track of sorted token order.
    uint256 internal waDaiIdx;
    uint256 internal waUsdcIdx;

    address internal waDAIBufferPool;
    address internal waUSDCBufferPool;

    address internal boostedPool;

    // `defaultAmount` from BaseVaultTest (e.g., 1,000), corresponds to the funding of the buffer.
    // We will swap with 10% of the buffer
    uint256 internal swapAmount = defaultAmount / 10;
    // The boosted pool will have 10x the liquidity of the buffer
    uint256 internal boostedPoolAmount = defaultAmount * 10;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        waDAI = new ERC4626TestToken(dai, "Wrapped aDAI", "waDAI", 18);
        // "USDC" is deliberately 18 decimals to test one thing at a time.
        waUSDC = new ERC4626TestToken(usdc, "Wrapped aUSDC", "waUSDC", 18);

        bufferFactory = new ERC4626BufferPoolFactory(vault, 365 days);

        (waDaiIdx, waUsdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));

        initializeBuffers();
        initializeBoostedPool();

        dai.mint(address(waDAI), swapAmount);
        waDAI.mint(swapAmount, alice);
    }

    function initializeBuffers() private {
        // Create and fund buffer pools
        dai.mint(address(waDAI), defaultAmount);
        waDAI.mint(defaultAmount, alice);
        usdc.mint(address(waUSDC), defaultAmount);
        waUSDC.mint(defaultAmount, alice);

        waDAIBufferPool = bufferFactory.create(waDAI, address(0), getSalt(address(waDAI)));
        waUSDCBufferPool = bufferFactory.create(waUSDC, address(0), getSalt(address(waUSDC)));

        IERC20[] memory daiBufferTokens = InputHelpers.sortTokens(
            [address(waDAI), address(dai)].toMemoryArray().asIERC20()
        );

        vm.startPrank(alice);
        waDAI.approve(address(vault), type(uint256).max);

        router.initialize(
            address(waDAIBufferPool),
            daiBufferTokens,
            [defaultAmount, defaultAmount].toMemoryArray(),
            defaultAmount * 2 - MIN_BPT,
            false,
            bytes("")
        );

        IERC20[] memory usdcBufferTokens = InputHelpers.sortTokens(
            [address(waUSDC), address(usdc)].toMemoryArray().asIERC20()
        );

        waUSDC.approve(address(vault), type(uint256).max);
        router.initialize(
            address(waUSDCBufferPool),
            usdcBufferTokens,
            [defaultAmount, defaultAmount].toMemoryArray(),
            defaultAmount * 2 - MIN_BPT,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function initializeBoostedPool() private {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[waDaiIdx].token = IERC20(waDAI);
        tokenConfig[waUsdcIdx].token = IERC20(waUSDC);
        tokenConfig[0].tokenType = TokenType.ERC4626;
        tokenConfig[1].tokenType = TokenType.ERC4626;

        PoolMock newPool = new PoolMock(
            IVault(address(vault)),
            "Boosted Pool",
            "BOOSTYBOI",
            tokenConfig,
            true,
            365 days,
            address(0)
        );
        vm.label(address(newPool), "boosted pool");
        boostedPool = address(newPool);

        dai.mint(address(waDAI), boostedPoolAmount);
        waDAI.mint(boostedPoolAmount, bob);
        usdc.mint(address(waUSDC), boostedPoolAmount);
        waUSDC.mint(boostedPoolAmount, bob);

        vm.startPrank(bob);
        waDAI.approve(address(vault), type(uint256).max);
        waUSDC.approve(address(vault), type(uint256).max);

        router.initialize(
            address(boostedPool),
            InputHelpers.sortTokens([address(waDAI), address(waUSDC)].toMemoryArray().asIERC20()),
            [boostedPoolAmount, boostedPoolAmount].toMemoryArray(),
            boostedPoolAmount * 2 - MIN_BPT,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function testSwapPreconditions() public {
        // bob should have the full boostedPool BPT.
        assertEq(IERC20(boostedPool).balanceOf(bob), boostedPoolAmount * 2 - MIN_BPT);

        (IERC20[] memory tokens, , uint256[] memory balancesRaw, , ) = vault.getPoolTokenInfo(boostedPool);
        // The boosted pool should have `boostedPoolAmount` of both tokens.
        assertEq(address(tokens[waDaiIdx]), address(waDAI));
        assertEq(address(tokens[waUsdcIdx]), address(waUSDC));
        assertEq(balancesRaw[0], boostedPoolAmount);
        assertEq(balancesRaw[1], boostedPoolAmount);

        // alice should have all the buffer BPT.
        assertEq(IERC20(waDAIBufferPool).balanceOf(alice), defaultAmount * 2 - MIN_BPT);
        assertEq(IERC20(waUSDCBufferPool).balanceOf(alice), defaultAmount * 2 - MIN_BPT);

        // The buffer pools should each have `defaultAmount` of their respective tokens.
        (uint256 wrappedIdx, uint256 baseIdx) = getSortedIndexes(address(waDAI), address(dai));
        (tokens, , balancesRaw, , ) = vault.getPoolTokenInfo(waDAIBufferPool);
        assertEq(address(tokens[wrappedIdx]), address(waDAI));
        assertEq(address(tokens[baseIdx]), address(dai));
        assertEq(balancesRaw[0], defaultAmount);
        assertEq(balancesRaw[1], defaultAmount);

        (wrappedIdx, baseIdx) = getSortedIndexes(address(waUSDC), address(usdc));
        (tokens, , balancesRaw, , ) = vault.getPoolTokenInfo(waUSDCBufferPool);
        assertEq(address(tokens[wrappedIdx]), address(waUSDC));
        assertEq(address(tokens[baseIdx]), address(usdc));
        assertEq(balancesRaw[0], defaultAmount);
        assertEq(balancesRaw[1], defaultAmount);
    }
}
