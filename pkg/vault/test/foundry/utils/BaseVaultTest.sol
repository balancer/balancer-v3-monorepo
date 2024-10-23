// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { HookFlags, FEE_SCALING_FACTOR, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IRouterMock } from "@balancer-labs/v3-interfaces/contracts/test/IRouterMock.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { CompositeLiquidityRouterMock } from "../../../contracts/test/CompositeLiquidityRouterMock.sol";
import { BasicAuthorizerMock } from "../../../contracts/test/BasicAuthorizerMock.sol";
import { RateProviderMock } from "../../../contracts/test/RateProviderMock.sol";
import { BatchRouterMock } from "../../../contracts/test/BatchRouterMock.sol";
import { PoolFactoryMock } from "../../../contracts/test/PoolFactoryMock.sol";
import { PoolHooksMock } from "../../../contracts/test/PoolHooksMock.sol";
import { RouterMock } from "../../../contracts/test/RouterMock.sol";
import { VaultStorage } from "../../../contracts/VaultStorage.sol";
import { PoolMock } from "../../../contracts/test/PoolMock.sol";

import { VaultContractsDeployer } from "./VaultContractsDeployer.sol";
import { Permit2Helpers } from "./Permit2Helpers.sol";

abstract contract BaseVaultTest is VaultContractsDeployer, VaultStorage, BaseTest, Permit2Helpers {
    using CastingHelpers for address[];
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    struct Balances {
        uint256[] userTokens;
        uint256 userBpt;
        uint256[] aliceTokens;
        uint256 aliceBpt;
        uint256[] bobTokens;
        uint256 bobBpt;
        uint256[] hookTokens;
        uint256 hookBpt;
        uint256[] lpTokens;
        uint256 lpBpt;
        uint256[] vaultTokens;
        uint256[] vaultReserves;
        uint256[] poolTokens;
        uint256 poolSupply;
        uint256 poolInvariant;
        uint256[] swapFeeAmounts;
        uint256[] yieldFeeAmounts;
    }

    // Pool limits.
    uint256 internal constant POOL_MINIMUM_TOTAL_SUPPLY = 1e6;
    uint256 internal constant PRODUCTION_MIN_TRADE_AMOUNT = 1e6;

    // ERC4626 buffer limits.
    uint256 internal constant BUFFER_MINIMUM_TOTAL_SUPPLY = 1e4;
    uint256 internal constant PRODUCTION_MIN_WRAP_AMOUNT = 1e3;

    bytes32 internal constant ZERO_BYTES32 = 0x0000000000000000000000000000000000000000000000000000000000000000;
    bytes32 internal constant ONE_BYTES32 = 0x0000000000000000000000000000000000000000000000000000000000000001;

    // Main contract mocks.
    IVaultMock internal vault;
    IVaultExtension internal vaultExtension;
    IVaultAdmin internal vaultAdmin;
    IRouterMock internal router;
    BatchRouterMock internal batchRouter;
    PoolFactoryMock internal factoryMock;
    RateProviderMock internal rateProvider;
    CompositeLiquidityRouterMock internal compositeLiquidityRouter;
    BasicAuthorizerMock internal authorizer;

    // Fee controller deployed with the Vault.
    IProtocolFeeController internal feeController;
    // Pool for tests.
    address internal pool;
    // Pool Hooks.
    address internal poolHooksContract;

    // Default amount to use in tests for user operations.
    uint256 internal defaultAmount = 1e3 * 1e18;
    // Default amount round up.
    uint256 internal defaultAmountRoundUp = defaultAmount + 1;
    // Default amount round down.
    uint256 internal defaultAmountRoundDown = defaultAmount - 2;
    // Default amount of BPT to use in tests for user operations.
    uint256 internal bptAmount = 2e3 * 1e18;
    // Default amount of BPT round down.
    uint256 internal bptAmountRoundDown = bptAmount - 2;
    // Amount to use to init the mock pool.
    uint256 internal poolInitAmount = 1e3 * 1e18;
    // Default rate for the rate provider mock.
    uint256 internal mockRate = 2e18;
    // Default swap fee percentage.
    uint256 internal swapFeePercentage = 1e16; // 1%
    // Default protocol swap fee percentage.
    uint64 internal protocolSwapFeePercentage = 50e16; // 50%

    // VaultMock can override min trade amount; tests shall use 0 by default to simplify fuzz tests.
    // Min trade amount is meant to be an extra protection against unknown rounding errors; the Vault should still work
    // without it, so it can be zeroed out in general.
    // Change this value before calling `setUp` to test under real conditions.
    uint256 vaultMockMinTradeAmount = 0;

    // VaultMock can override min wrap amount; tests shall use 0 by default to simplify fuzz tests.
    // Min wrap amount is meant to be an extra protection against unknown rounding errors; the Vault should still work
    // without it, so it can be zeroed out in general.
    // Change this value before calling `setUp` to test under real conditions.
    uint256 vaultMockMinWrapAmount = 0;

    // Applies to Weighted Pools.
    uint256 internal constant BASE_MIN_SWAP_FEE = 1e12; // 0.00001%
    uint256 internal constant BASE_MAX_SWAP_FEE = 10e16; // 10%

    function setUp() public virtual override {
        BaseTest.setUp();
        _setUpBaseVaultTest();
        // Add initial liquidity
        initPool();
    }

    function _setUpBaseVaultTest() internal {
        vault = deployVaultMock(vaultMockMinTradeAmount, vaultMockMinWrapAmount);

        vm.label(address(vault), "vault");
        vaultExtension = IVaultExtension(vault.getVaultExtension());
        vm.label(address(vaultExtension), "vaultExtension");
        vaultAdmin = IVaultAdmin(vault.getVaultAdmin());
        vm.label(address(vaultAdmin), "vaultAdmin");
        authorizer = BasicAuthorizerMock(address(vault.getAuthorizer()));
        vm.label(address(authorizer), "authorizer");
        factoryMock = PoolFactoryMock(address(vault.getPoolFactoryMock()));
        vm.label(address(factoryMock), "factory");
        router = IRouterMock(address(deployRouterMock(IVault(address(vault)), weth, permit2)));
        vm.label(address(router), "router");
        batchRouter = deployBatchRouterMock(IVault(address(vault)), weth, permit2);
        vm.label(address(batchRouter), "batch router");
        compositeLiquidityRouter = new CompositeLiquidityRouterMock(IVault(address(vault)), weth, permit2);
        vm.label(address(compositeLiquidityRouter), "composite liquidity router");
        feeController = vault.getProtocolFeeController();
        vm.label(address(feeController), "fee controller");

        poolHooksContract = createHook();
        pool = createPool();

        // Approve vault allowances.
        for (uint256 i = 0; i < users.length; ++i) {
            address user = users[i];
            vm.startPrank(user);
            approveForSender();
            vm.stopPrank();
        }
        if (pool != address(0)) {
            approveForPool(IERC20(pool));
        }
    }

    function approveForSender() internal virtual {
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokens[i].approve(address(permit2), type(uint256).max);
            permit2.approve(address(tokens[i]), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(tokens[i]), address(batchRouter), type(uint160).max, type(uint48).max);
            permit2.approve(address(tokens[i]), address(compositeLiquidityRouter), type(uint160).max, type(uint48).max);
        }

        for (uint256 i = 0; i < erc4626Tokens.length; ++i) {
            erc4626Tokens[i].approve(address(permit2), type(uint256).max);
            permit2.approve(address(erc4626Tokens[i]), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(erc4626Tokens[i]), address(batchRouter), type(uint160).max, type(uint48).max);
            permit2.approve(
                address(erc4626Tokens[i]),
                address(compositeLiquidityRouter),
                type(uint160).max,
                type(uint48).max
            );

            // Approve deposits from sender.
            IERC20 underlying = IERC20(erc4626Tokens[i].asset());
            underlying.approve(address(erc4626Tokens[i]), type(uint160).max);
        }
    }

    function approveForPool(IERC20 bpt) internal virtual {
        for (uint256 i = 0; i < users.length; ++i) {
            vm.startPrank(users[i]);

            bpt.approve(address(router), type(uint256).max);
            bpt.approve(address(batchRouter), type(uint256).max);
            bpt.approve(address(compositeLiquidityRouter), type(uint256).max);

            IERC20(bpt).approve(address(permit2), type(uint256).max);
            permit2.approve(address(bpt), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(bpt), address(batchRouter), type(uint160).max, type(uint48).max);
            permit2.approve(address(bpt), address(compositeLiquidityRouter), type(uint160).max, type(uint48).max);

            vm.stopPrank();
        }
    }

    function initPool() internal virtual {
        vm.startPrank(lp);
        _initPool(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();
    }

    function _initPool(
        address poolToInit,
        uint256[] memory amountsIn,
        uint256 minBptOut
    ) internal virtual returns (uint256 bptOut) {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(poolToInit);

        return router.initialize(poolToInit, tokens, amountsIn, minBptOut, false, bytes(""));
    }

    function createPool() internal virtual returns (address) {
        return _createPool([address(dai), address(usdc)].toMemoryArray(), "pool");
    }

    function _createPool(address[] memory tokens, string memory label) internal virtual returns (address) {
        address newPool = factoryMock.createPool("ERC20 Pool", "ERC20POOL");
        vm.label(newPool, label);

        factoryMock.registerTestPool(newPool, vault.buildTokenConfig(tokens.asIERC20()), poolHooksContract, lp);

        return newPool;
    }

    function createHook() internal virtual returns (address) {
        // Sets all flags to false.
        HookFlags memory hookFlags;
        return _createHook(hookFlags);
    }

    function _createHook(HookFlags memory hookFlags) internal virtual returns (address) {
        PoolHooksMock newHook = deployPoolHooksMock(IVault(address(vault)));
        // Allow pools built with factoryMock to use the poolHooksMock.
        newHook.allowFactory(address(factoryMock));
        // Configure pool hook flags.
        newHook.setHookFlags(hookFlags);
        vm.label(address(newHook), "pool hooks");
        return address(newHook);
    }

    function setSwapFeePercentage(uint256 percentage) internal {
        _setSwapFeePercentage(pool, percentage);
    }

    function _setSwapFeePercentage(address setPool, uint256 percentage) internal {
        vault.manuallySetSwapFee(setPool, percentage);
    }

    function getBalances(address user) internal view returns (Balances memory balances) {
        return getBalances(user, Rounding.ROUND_DOWN);
    }

    function getBalances(address user, Rounding invariantRounding) internal view returns (Balances memory balances) {
        balances.userBpt = IERC20(pool).balanceOf(user);
        balances.aliceBpt = IERC20(pool).balanceOf(alice);
        balances.bobBpt = IERC20(pool).balanceOf(bob);
        balances.hookBpt = IERC20(pool).balanceOf(poolHooksContract);
        balances.lpBpt = IERC20(pool).balanceOf(lp);

        balances.poolSupply = IERC20(pool).totalSupply();

        (IERC20[] memory tokens, , uint256[] memory poolBalances, uint256[] memory lastBalancesLiveScaled18) = vault
            .getPoolTokenInfo(pool);
        balances.poolTokens = poolBalances;
        uint256 numTokens = tokens.length;

        balances.poolInvariant = IBasePool(pool).computeInvariant(lastBalancesLiveScaled18, invariantRounding);
        balances.userTokens = new uint256[](numTokens);
        balances.aliceTokens = new uint256[](numTokens);
        balances.bobTokens = new uint256[](numTokens);
        balances.hookTokens = new uint256[](numTokens);
        balances.lpTokens = new uint256[](numTokens);
        balances.vaultTokens = new uint256[](numTokens);
        balances.vaultReserves = new uint256[](numTokens);
        balances.swapFeeAmounts = new uint256[](numTokens);
        balances.yieldFeeAmounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            // Don't assume token ordering.
            balances.userTokens[i] = tokens[i].balanceOf(user);
            balances.aliceTokens[i] = tokens[i].balanceOf(alice);
            balances.bobTokens[i] = tokens[i].balanceOf(bob);
            balances.hookTokens[i] = tokens[i].balanceOf(poolHooksContract);
            balances.lpTokens[i] = tokens[i].balanceOf(lp);
            balances.vaultTokens[i] = tokens[i].balanceOf(address(vault));
            balances.vaultReserves[i] = vault.getReservesOf(tokens[i]);
            balances.swapFeeAmounts[i] = vault.manualGetAggregateSwapFeeAmount(pool, tokens[i]);
            balances.yieldFeeAmounts[i] = vault.manualGetAggregateYieldFeeAmount(pool, tokens[i]);
        }
    }

    /// @dev A different function is needed to measure token balances when tracking tokens across multiple pools.
    function getBalances(address user, IERC20[] memory tokensToTrack) internal view returns (Balances memory balances) {
        balances.userBpt = IERC20(pool).balanceOf(user);
        balances.aliceBpt = IERC20(pool).balanceOf(alice);
        balances.bobBpt = IERC20(pool).balanceOf(bob);
        balances.hookBpt = IERC20(pool).balanceOf(poolHooksContract);
        balances.lpBpt = IERC20(pool).balanceOf(lp);

        uint256 numTokens = tokensToTrack.length;

        balances.userTokens = new uint256[](numTokens);
        balances.aliceTokens = new uint256[](numTokens);
        balances.bobTokens = new uint256[](numTokens);
        balances.hookTokens = new uint256[](numTokens);
        balances.lpTokens = new uint256[](numTokens);
        balances.vaultTokens = new uint256[](numTokens);
        balances.vaultReserves = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            // Don't assume token ordering.
            balances.userTokens[i] = tokensToTrack[i].balanceOf(user);
            balances.aliceTokens[i] = tokensToTrack[i].balanceOf(alice);
            balances.bobTokens[i] = tokensToTrack[i].balanceOf(bob);
            balances.hookTokens[i] = tokensToTrack[i].balanceOf(poolHooksContract);
            balances.lpTokens[i] = tokensToTrack[i].balanceOf(lp);
            balances.vaultTokens[i] = tokensToTrack[i].balanceOf(address(vault));
            balances.vaultReserves[i] = vault.getReservesOf(tokensToTrack[i]);
        }
    }

    function getSalt(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function _prankStaticCall() internal {
        // Prank address 0x0 for both msg.sender and tx.origin (to identify as a staticcall).
        vm.prank(address(0), address(0));
    }
}
