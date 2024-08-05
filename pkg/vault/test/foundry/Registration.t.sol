// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { HooksConfigLib } from "../../contracts/lib/HooksConfigLib.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract RegistrationTest is BaseVaultTest {
    using HooksConfigLib for PoolConfigBits;
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    IERC20[] standardPoolTokens;
    TokenConfig[] standardTokenConfig;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        standardPoolTokens = InputHelpers.sortTokens([address(dai), address(usdc)].toMemoryArray().asIERC20());

        pool = address(new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL"));
    }

    // Do not register the pool in the base test.
    function createPool() internal pure override returns (address) {
        return address(0);
    }

    function initPool() internal override {}

    function testRegisterPoolTwice() public {
        PoolRoleAccounts memory roleAccounts;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(standardPoolTokens);
        LiquidityManagement memory liquidityManagement;

        vault.registerPool(pool, tokenConfig, 0, 0, false, roleAccounts, address(0), liquidityManagement);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolAlreadyRegistered.selector, pool));
        vault.registerPool(pool, tokenConfig, 0, 0, false, roleAccounts, address(0), liquidityManagement);
    }

    function testRegisterPoolBelowMinTokens() public {
        PoolRoleAccounts memory roleAccounts;
        TokenConfig[] memory tokenConfig = new TokenConfig[](vault.getMinimumPoolTokens() - 1);
        LiquidityManagement memory liquidityManagement;

        vm.expectRevert(IVaultErrors.MinTokens.selector);
        vault.registerPool(pool, tokenConfig, 0, 0, false, roleAccounts, address(0), liquidityManagement);
    }

    function testRegisterPoolAboveMaxTokens() public {
        PoolRoleAccounts memory roleAccounts;
        TokenConfig[] memory tokenConfig = new TokenConfig[](vault.getMaximumPoolTokens() + 1);
        LiquidityManagement memory liquidityManagement;

        vm.expectRevert(IVaultErrors.MaxTokens.selector);
        vault.registerPool(pool, tokenConfig, 0, 0, false, roleAccounts, address(0), liquidityManagement);
    }

    function testRegisterPoolTokensNotSorted() public {
        PoolRoleAccounts memory roleAccounts;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(standardPoolTokens);
        // Disorder the tokens
        TokenConfig memory tmp = tokenConfig[0];
        tokenConfig[0] = tokenConfig[1];
        tokenConfig[1] = tmp;
        LiquidityManagement memory liquidityManagement;

        vm.expectRevert(InputHelpers.TokensNotSorted.selector);
        vault.registerPool(pool, tokenConfig, 0, 0, false, roleAccounts, address(0), liquidityManagement);
    }

    function testRegisterPoolAddressZeroToken() public {
        PoolRoleAccounts memory roleAccounts;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(standardPoolTokens);
        tokenConfig[0].token = IERC20(address(0));
        LiquidityManagement memory liquidityManagement;

        vm.expectRevert(IVaultErrors.InvalidToken.selector);
        vault.registerPool(pool, tokenConfig, 0, 0, false, roleAccounts, address(0), liquidityManagement);
    }

    function testRegisterPoolAddressPoolToken() public {
        PoolRoleAccounts memory roleAccounts;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            InputHelpers.sortTokens([address(pool), address(usdc)].toMemoryArray().asIERC20())
        );
        tokenConfig[0].token = IERC20(address(0));
        LiquidityManagement memory liquidityManagement;

        vm.expectRevert(IVaultErrors.InvalidToken.selector);
        vault.registerPool(pool, tokenConfig, 0, 0, false, roleAccounts, address(0), liquidityManagement);
    }

    function testRegisterPoolSameAddressToken() public {
        PoolRoleAccounts memory roleAccounts;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(usdc), address(usdc)].toMemoryArray().asIERC20()
        );
        LiquidityManagement memory liquidityManagement;

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.TokenAlreadyRegistered.selector, usdc));
        vault.registerPool(pool, tokenConfig, 0, 0, false, roleAccounts, address(0), liquidityManagement);
    }

    function testRegisterSetSwapFeePercentage__Fuzz(uint256 swapFeePercentage) public {
        swapFeePercentage = bound(swapFeePercentage, 0, FixedPoint.ONE);
        PoolRoleAccounts memory roleAccounts;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(standardPoolTokens);
        LiquidityManagement memory liquidityManagement;

        vault.registerPool(
            pool,
            tokenConfig,
            swapFeePercentage,
            0,
            false,
            roleAccounts,
            address(0),
            liquidityManagement
        );
        // Stored value is truncated.
        assertEq(
            vault.getStaticSwapFeePercentage(pool),
            (swapFeePercentage / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR,
            "Wrong swap fee percentage"
        );
    }

    function testRegisterSetSwapFeePercentageAboveMax() public {
        swapFeePercentage = FixedPoint.ONE + 1;
        PoolRoleAccounts memory roleAccounts;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(standardPoolTokens);
        LiquidityManagement memory liquidityManagement;

        vm.expectRevert(IVaultErrors.SwapFeePercentageTooHigh.selector);
        vault.registerPool(
            pool,
            tokenConfig,
            swapFeePercentage,
            0,
            false,
            roleAccounts,
            address(0),
            liquidityManagement
        );
    }

    function testRegisterSetPauseWindowEndTime__Fuzz(uint32 pauseWindowEndTime) public {
        PoolRoleAccounts memory roleAccounts;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(standardPoolTokens);
        LiquidityManagement memory liquidityManagement;

        vault.registerPool(
            pool,
            tokenConfig,
            0,
            pauseWindowEndTime,
            false,
            roleAccounts,
            address(0),
            liquidityManagement
        );
        PoolConfig memory poolConfig = vault.getPoolConfig(pool);
        assertEq(poolConfig.pauseWindowEndTime, pauseWindowEndTime, "Wrong pause window end time");
    }

    function testRegisterSetTokenDecimalDiffs__Fuzz(uint256 decimalDiff) public {
        uint8 decimalDiffDai = uint8(bound(decimalDiff, 0, 18));
        uint8 decimalDiffUsdc = uint8(bound(decimalDiffDai * 10, 0, 18));
        (uint256 daiIdx, uint256 usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        PoolRoleAccounts memory roleAccounts;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(standardPoolTokens);
        LiquidityManagement memory liquidityManagement;
        vm.mockCall(address(dai), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(decimalDiffDai));
        vm.mockCall(
            address(usdc),
            abi.encodeWithSelector(IERC20Metadata.decimals.selector),
            abi.encode(decimalDiffUsdc)
        );
        vault.registerPool(pool, tokenConfig, 0, 0, false, roleAccounts, address(0), liquidityManagement);
        // Test end to end that the decimal scaling factors are correct
        (uint256[] memory decimalScalingFactors, ) = vault.getPoolTokenRates(pool);
        assertEq(decimalScalingFactors[daiIdx], 1e18 * 10 ** (18 - decimalDiffDai), "Wrong dai decimal scaling factor");
        assertEq(
            decimalScalingFactors[usdcIdx],
            1e18 * 10 ** (18 - decimalDiffUsdc),
            "Wrong usdc decimal scaling factor"
        );
    }

    function testRegisterSetWrongTokenDecimalDiffs() public {
        PoolRoleAccounts memory roleAccounts;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(standardPoolTokens);
        LiquidityManagement memory liquidityManagement;
        vm.mockCall(address(dai), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(19));

        vm.expectRevert(stdError.arithmeticError);
        vault.registerPool(pool, tokenConfig, 0, 0, false, roleAccounts, address(0), liquidityManagement);
    }

    function testRegisterEmitsEvents() public {
        uint256 swapFeePercentage = 3.1415e10;
        uint32 pauseWindowEndTime = 2.71e4;
        PoolRoleAccounts memory roleAccounts = PoolRoleAccounts({
            pauseManager: address(1),
            swapFeeManager: address(2),
            poolCreator: address(3)
        });
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(standardPoolTokens);
        LiquidityManagement memory liquidityManagement = LiquidityManagement({
            disableUnbalancedLiquidity: true,
            enableAddLiquidityCustom: true,
            enableRemoveLiquidityCustom: false,
            enableDonation: true
        });

        PoolConfigBits config;

        vm.expectEmit();
        emit IVaultEvents.SwapFeePercentageChanged(pool, swapFeePercentage);
        vm.expectEmit();
        emit IVaultEvents.PoolRegistered(
            pool,
            address(this),
            tokenConfig,
            swapFeePercentage,
            pauseWindowEndTime,
            roleAccounts,
            config.toHooksConfig(IHooks(address(0))),
            liquidityManagement
        );
        vault.registerPool(
            pool,
            tokenConfig,
            swapFeePercentage,
            pauseWindowEndTime,
            false,
            roleAccounts,
            address(0),
            liquidityManagement
        );
    }
}
