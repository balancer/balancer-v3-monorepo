// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { PoolFactoryMock } from "../../contracts/test/PoolFactoryMock.sol";
import { ERC4626BufferPoolFactory } from "../../contracts/factories/ERC4626BufferPoolFactory.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultTokenTest is BaseVaultTest {
    using ArrayHelpers for *;

    address poolAddress;

    PoolFactoryMock poolFactory;
    ERC4626BufferPoolFactory bufferFactory;

    address waDAIBuffer;
    address cDAIBuffer;
    address waUSDCBuffer;

    ERC4626TestToken waDAI;
    ERC4626TestToken cDAI;
    ERC4626TestToken waUSDC;

    // For two-token pools with waDAI/waUSDC, keep track of sorted token order.
    uint256 internal waDaiIdx;
    uint256 internal waUsdcIdx;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        waDAI = new ERC4626TestToken(dai, "Wrapped aDAI", "waDAI", 18);
        cDAI = new ERC4626TestToken(dai, "Wrapped cDAI", "cDAI", 18);
        waUSDC = new ERC4626TestToken(usdc, "Wrapped aUSDC", "waUSDC", 6);

        poolFactory = new PoolFactoryMock(vault, 365 days);
        bufferFactory = new ERC4626BufferPoolFactory(vault, 365 days);

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
        (waDaiIdx, waUsdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));
    }

    function createPool() internal override returns (address) {
        poolAddress = vm.addr(1);

        return poolAddress;
    }

    function initPool() internal override {
        // Do nothing for this test
    }

    function testGetRegularPoolTokens() public {
        registerBuffers();
        registerPool();

        IERC20[] memory tokens = vault.getPoolTokens(poolAddress);

        assertEq(tokens.length, 2);

        assertEq(address(tokens[waDaiIdx]), address(waDAI));
        assertEq(address(tokens[waUsdcIdx]), address(waUSDC));
    }

    function testGetBufferPoolTokens() public {
        registerBuffers();
        registerPool();

        // Calling `getPoolTokens` on a Buffer Pool should return the actual registered tokens.
        validateBufferPool(
            waDAIBuffer,
            InputHelpers.sortTokens([address(waDAI), address(dai)].toMemoryArray().asIERC20())
        );
        validateBufferPool(
            waUSDCBuffer,
            InputHelpers.sortTokens([address(waUSDC), address(usdc)].toMemoryArray().asIERC20())
        );
    }

    function testInvalidYieldExemptWrappedToken() public {
        registerBuffers();

        // yield-exampt ERC4626 token is invalid
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[waDaiIdx].token = IERC20(waDAI);
        tokenConfig[waUsdcIdx].token = IERC20(waUSDC);
        tokenConfig[0].tokenType = TokenType.ERC4626;
        tokenConfig[0].yieldFeeExempt = true;
        tokenConfig[1].tokenType = TokenType.ERC4626;

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.InvalidTokenConfiguration.selector));
        _registerPool(tokenConfig);
    }

    function testInvalidStandardTokenWithRateProvider() public {
        // Standard token with a rate provider is invalid
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[daiIdx].token = IERC20(dai);
        tokenConfig[0].rateProvider = IRateProvider(waDAI);
        tokenConfig[usdcIdx].token = IERC20(usdc);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.InvalidTokenConfiguration.selector));
        _registerPool(tokenConfig);
    }

    function testInvalidRateTokenWithoutProvider() public {
        // Rated token without a rate provider is invalid

        (uint256 ethIdx, uint256 localUsdcIdx) = getSortedIndexes(address(wsteth), address(usdc));

        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[ethIdx].token = IERC20(wsteth);
        tokenConfig[ethIdx].tokenType = TokenType.WITH_RATE;
        tokenConfig[localUsdcIdx].token = IERC20(usdc);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.InvalidTokenConfiguration.selector));
        _registerPool(tokenConfig);
    }

    function testRegistrationWithERC4626Tokens() public {
        registerBuffers();

        // Regular pool cannot have a buffer token with the same base as an existing standard token.
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[waDaiIdx].token = IERC20(waDAI);
        tokenConfig[waUsdcIdx].token = IERC20(waUSDC);
        tokenConfig[0].tokenType = TokenType.ERC4626;
        tokenConfig[1].tokenType = TokenType.ERC4626;

        _registerPool(tokenConfig);

        // Check that actual registered tokens, vs "reported" ones, are the wrappers.
        (IERC20[] memory tokens, TokenType[] memory tokenTypes, , , ) = vault.getPoolTokenInfo(pool);

        assertEq(address(tokens[waDaiIdx]), address(waDAI));
        assertEq(address(tokens[waUsdcIdx]), address(waUSDC));
        assertTrue(tokenTypes[0] == TokenType.ERC4626);
        assertTrue(tokenTypes[1] == TokenType.ERC4626);
    }

    function registerBuffers() private {
        // Establish assets and supply so that buffer creation doesn't fail
        dai.mint(address(waDAI), 1000e18);
        waDAI.mint(1000e18, alice);
        dai.mint(address(cDAI), 1000e18);
        cDAI.mint(1000e18, alice);
        usdc.mint(address(waUSDC), 1000e18);
        waUSDC.mint(1000e18, alice);

        vm.startPrank(alice);
        waDAIBuffer = bufferFactory.create(waDAI, address(0), getSalt(address(waDAI)));
        cDAIBuffer = bufferFactory.create(cDAI, address(0), getSalt(address(cDAI)));
        waUSDCBuffer = bufferFactory.create(waUSDC, address(0), getSalt(address(waUSDC)));
        vm.stopPrank();
    }

    function registerPool() private {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[waDaiIdx].token = IERC20(waDAI);
        tokenConfig[waUsdcIdx].token = IERC20(waUSDC);
        tokenConfig[0].tokenType = TokenType.ERC4626;
        tokenConfig[1].tokenType = TokenType.ERC4626;

        _registerPool(tokenConfig);
    }

    function _registerPool(TokenConfig[] memory tokenConfig) private {
        poolFactory.registerPool(
            poolAddress,
            tokenConfig,
            address(0),
            PoolHooks({
                shouldCallBeforeInitialize: false,
                shouldCallAfterInitialize: false,
                shouldCallBeforeAddLiquidity: false,
                shouldCallAfterAddLiquidity: false,
                shouldCallBeforeRemoveLiquidity: false,
                shouldCallAfterRemoveLiquidity: false,
                shouldCallBeforeSwap: false,
                shouldCallAfterSwap: false
            }),
            LiquidityManagement({ supportsAddLiquidityCustom: false, supportsRemoveLiquidityCustom: false })
        );
    }

    function validateBufferPool(address pool, IERC20[] memory expectedTokens) private {
        IERC20[] memory actualTokens = vault.getPoolTokens(pool);

        assertEq(actualTokens.length, expectedTokens.length);

        for (uint256 i = 0; i < expectedTokens.length; i++) {
            assertEq(address(actualTokens[i]), address(expectedTokens[i]));
        }
    }
}
