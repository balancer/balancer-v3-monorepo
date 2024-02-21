// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultMain } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";

import { PoolFactoryMock } from "../../contracts/test/PoolFactoryMock.sol";
import { ERC4626BufferPoolFactory } from "../../contracts/factories/ERC4626BufferPoolFactory.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultTokenTest is BaseVaultTest {
    using ArrayHelpers for *;

    address poolAddress;

    PoolFactoryMock poolFactory;
    ERC4626BufferPoolFactory bufferFactory;

    address waDAIBuffer;
    address waUSDCBuffer;

    ERC4626TestToken waDAI;
    ERC4626TestToken waUSDC;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        waDAI = new ERC4626TestToken(dai, "Wrapped aDAI", "waDAI", 18);
        waUSDC = new ERC4626TestToken(usdc, "Wrapped aUSDC", "waUSDC", 6);

        poolFactory = new PoolFactoryMock(vault, 365 days);
        bufferFactory = new ERC4626BufferPoolFactory(vault, 365 days);
    }

    function createPool() internal override returns (address) {
        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");
        vm.label(address(newPool), "pool");

        poolAddress = address(newPool);

        return poolAddress;
    }

    function initPool() internal override {
        // Do nothing for this test
    }

    function testERC4626PoolWithoutBuffers() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrappedTokenBufferNotRegistered.selector));
        registerPool();
    }

    function testGetRegularPoolTokens() public {
        registerBuffers();
        registerPool();

        // Calling `getPoolTokens` on a regular pool should return the base tokens for any ERC4626 tokens.
        IERC20[] memory tokens = vault.getPoolTokens(poolAddress);

        assertEq(tokens.length, 2);

        assertEq(address(tokens[0]), address(dai));
        assertEq(address(tokens[1]), address(usdc));
    }

    function testGetBufferPoolTokens() public {
        registerBuffers();
        registerPool();

        // Calling `getPoolTokens` on a Buffer Pool should return the actual registered tokens.
        validateBufferPool(waDAIBuffer, [address(waDAI), address(dai)].toMemoryArray());
        validateBufferPool(waUSDCBuffer, [address(waUSDC), address(usdc)].toMemoryArray());
    }

    function testInvalidYieldExemptWrappedToken() public {
        registerBuffers();

        // yield-exampt ERC4626 token is invalid
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[0].token = IERC20(waDAI);
        tokenConfig[1].token = IERC20(waUSDC);
        tokenConfig[0].tokenType = TokenType.ERC4626;
        tokenConfig[0].yieldFeeExempt = true;
        tokenConfig[1].tokenType = TokenType.ERC4626;

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.InvalidTokenConfiguration.selector));
        _registerPool(tokenConfig);
    }

    function testInvalidStandardTokenWithRateProvider() public {
        // Standard token with a rate provider is invalid
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[0].token = IERC20(dai);
        tokenConfig[0].rateProvider = IRateProvider(waDAI);
        tokenConfig[1].token = IERC20(usdc);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.InvalidTokenConfiguration.selector));
        _registerPool(tokenConfig);
    }

    function testInvalidRateTokenWithoutProvider() public {
        // Rated token without a rate provider is invalid
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[0].token = IERC20(wsteth);
        tokenConfig[0].tokenType = TokenType.WITH_RATE;
        tokenConfig[1].token = IERC20(usdc);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.InvalidTokenConfiguration.selector));
        _registerPool(tokenConfig);
    }

    function registerBuffers() private {
        // Buffer Pool creation is permissioned.
        authorizer.grantRole(bufferFactory.getActionId(ERC4626BufferPoolFactory.create.selector), alice);

        // Establish assets and supply so that buffer creation doesn't fail
        dai.mint(address(waDAI), 1000e18);
        waDAI.mint(1000e18, alice);
        usdc.mint(address(waUSDC), 1000e18);
        waUSDC.mint(1000e18, alice);

        vm.startPrank(alice);
        waDAIBuffer = bufferFactory.create(waDAI, address(0), getSalt(address(waDAI)));
        waUSDCBuffer = bufferFactory.create(waUSDC, address(0), getSalt(address(waUSDC)));
        vm.stopPrank();
    }

    function registerPool() private {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[0].token = IERC20(waDAI);
        tokenConfig[1].token = IERC20(waUSDC);
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

    function getSalt(address addr) private pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function validateBufferPool(address pool, address[] memory expectedTokens) private {
        IERC20[] memory actualTokens = vault.getPoolTokens(pool);

        assertEq(actualTokens.length, expectedTokens.length);

        for (uint256 i = 0; i < expectedTokens.length; i++) {
            assertEq(address(actualTokens[i]), expectedTokens[i]);
        }
    }
}
