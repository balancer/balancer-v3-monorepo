// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TokenInfo, SwapKind, PoolSwapParams } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    TokenConfig,
    TokenType,
    LiquidityManagement,
    PoolRoleAccounts
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

import { PoolFactoryMock } from "../../contracts/test/PoolFactoryMock.sol";
import { PoolHooksMock } from "../../contracts/test/PoolHooksMock.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultTokenTest is BaseVaultTest {
    PoolFactoryMock poolFactory;

    ERC4626TestToken cDAI;

    PoolMock defaultPool;
    // For two-token pools with waDAI/waUSDC, keep track of sorted token order.
    uint256 internal waDaiIdx;
    uint256 internal waUsdcIdx;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        cDAI = new ERC4626TestToken(dai, "Wrapped cDAI", "cDAI", 18);

        poolFactory = deployPoolFactoryMock(vault, 365 days);

        // Allow pools from factory poolFactory to use the hook PoolHooksMock.
        PoolHooksMock(poolHooksContract()).allowFactory(address(poolFactory));

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
        (waDaiIdx, waUsdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));

        defaultPool = address(deployPoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL"));
    }

    function createPool() internal pure override returns (address, bytes memory) {
        return (address(0), new bytes(0));
    }

    function initPool() internal override {
        // Do nothing for this test.
    }

    function testGetRegularPoolTokens() public {
        registerBuffers();
        registerPool();

        IERC20[] memory tokens = vault.getPoolTokens(defaultPool);

        assertEq(tokens.length, 2);

        assertEq(address(tokens[waDaiIdx]), address(waDAI));
        assertEq(address(tokens[waUsdcIdx]), address(waUSDC));
    }

    function testInvalidStandardTokenWithRateProvider() public {
        // Standard token with a rate provider is invalid.
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[daiIdx].token = IERC20(dai);
        tokenConfig[0].rateProvider = IRateProvider(waDAI);
        tokenConfig[usdcIdx].token = IERC20(usdc);

        vm.expectRevert(IVaultErrors.InvalidTokenConfiguration.selector);
        _registerPool(tokenConfig);
    }

    function testInvalidRateTokenWithoutProvider() public {
        // Rated token without a rate provider is invalid.

        (uint256 ethIdx, uint256 localUsdcIdx) = getSortedIndexes(address(wsteth), address(usdc));

        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[ethIdx].token = IERC20(wsteth);
        tokenConfig[ethIdx].tokenType = TokenType.WITH_RATE;
        tokenConfig[localUsdcIdx].token = IERC20(usdc);

        vm.expectRevert(IVaultErrors.InvalidTokenConfiguration.selector);
        _registerPool(tokenConfig);
    }

    function testInvalidTokenDecimals() public {
        // This is technically a duplicate test (see `testRegisterSetWrongTokenDecimalDiffs` in Registration.t.sol),
        // but doesn't use a mockCall.
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        ERC20TestToken invalidToken = createERC20("INV", 19);
        uint256 invalidIdx;

        (invalidIdx, usdcIdx) = getSortedIndexes(address(invalidToken), address(usdc));

        tokenConfig[invalidIdx].token = IERC20(invalidToken);
        tokenConfig[usdcIdx].token = IERC20(usdc);

        vm.expectRevert(IVaultErrors.InvalidTokenDecimals.selector);
        _registerPool(tokenConfig);
    }

    function registerBuffers() private {
        // Establish assets and supply so that buffer creation doesn't fail.
        vm.startPrank(alice);

        dai.mint(alice, 2 * DEFAULT_AMOUNT);

        dai.approve(address(waDAI), DEFAULT_AMOUNT);
        waDAI.deposit(DEFAULT_AMOUNT, alice);

        dai.approve(address(cDAI), DEFAULT_AMOUNT);
        cDAI.deposit(DEFAULT_AMOUNT, alice);

        usdc.mint(alice, DEFAULT_AMOUNT);
        usdc.approve(address(waUSDC), DEFAULT_AMOUNT);
        waUSDC.deposit(DEFAULT_AMOUNT, alice);
        vm.stopPrank();
    }

    function registerPool() private {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[waDaiIdx].token = IERC20(waDAI);
        tokenConfig[waUsdcIdx].token = IERC20(waUSDC);
        tokenConfig[0].tokenType = TokenType.WITH_RATE;
        tokenConfig[1].tokenType = TokenType.WITH_RATE;
        tokenConfig[waDaiIdx].rateProvider = IRateProvider(waDAI);
        tokenConfig[waUsdcIdx].rateProvider = IRateProvider(waUSDC);

        _registerPool(tokenConfig);
    }

    function _registerPool(TokenConfig[] memory tokenConfig) private {
        LiquidityManagement memory liquidityManagement;
        PoolRoleAccounts memory roleAccounts;

        poolFactory.registerPool(defaultPool, tokenConfig, roleAccounts, poolHooksContract(), liquidityManagement);
    }
}
