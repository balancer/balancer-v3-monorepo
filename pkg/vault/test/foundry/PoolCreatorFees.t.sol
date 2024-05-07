// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract PoolCreatorFeesTest is BaseVaultTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;
    using SafeCast for *;

    uint256 private _defaultAmountToSwap;

    PoolMock exemptPool;

    function setUp() public override {
        BaseVaultTest.setUp();

        _defaultAmountToSwap = defaultAmount / 10;
    }

    function createPool() internal virtual override returns (address) {
        address[] memory tokens = [address(dai), address(usdc)].toMemoryArray();

        // Create a pool that is exempt from Protocol Swap Fees
        exemptPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "Exempt Pool");
        vm.label(address(exemptPool), "Exempt Pool");

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        factoryMock.registerGeneralTestPool(
            address(exemptPool),
            tokenConfig,
            0, // default swap fee (will be changed later)
            0, // pause time - doesn't matter here
            true, // exempt from protocol swap fees
            PoolRoleAccounts({ pauseManager: address(0), swapFeeManager: address(0), poolCreator: lp })
        );

        return _createPool(tokens, "swapPool");
    }

    function initPool() internal override {
        vm.startPrank(lp);
        _initPool(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        _initPool(address(exemptPool), [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();
    }

    function testPoolCreatorWasSet() public {
        assertEq(vault.getPoolCreator(pool), address(lp));
        assertEq(vault.getPoolCreator(address(exemptPool)), address(lp));
    }

    function testExemptFlagsWereSet() public {
        PoolConfig memory poolConfig = vault.getPoolConfig(pool);

        assertFalse(poolConfig.isExemptFromProtocolSwapFee);

        poolConfig = vault.getPoolConfig(address(exemptPool));
        assertTrue(poolConfig.isExemptFromProtocolSwapFee);
    }

    function testSwapWithoutFees() public {
        _swapExactInWithFees(address(pool), usdc, dai, _defaultAmountToSwap, 0, 0, 0, false);
    }

    function testSwapWithCreatorFee() public {
        uint256 amountToSwap = _defaultAmountToSwap;
        uint64 swapFeePercentage = 1e17; // 10%
        uint64 protocolFeePercentage = 3e17; // 30%
        uint64 poolCreatorFeePercentage = 5e17; // 50%

        _swapExactInWithFees(
            address(pool),
            usdc,
            dai,
            amountToSwap,
            swapFeePercentage,
            protocolFeePercentage,
            poolCreatorFeePercentage,
            true
        );
    }

    function testProtocolFeeExemptSwapWithCreatorFee() public {
        uint256 amountToSwap = _defaultAmountToSwap;
        uint64 swapFeePercentage = 1e17; // 10%
        uint64 protocolFeePercentage = 3e17; // 30%
        uint64 poolCreatorFeePercentage = 5e17; // 50%

        _swapExactInWithFees(
            address(exemptPool),
            usdc,
            dai,
            amountToSwap,
            swapFeePercentage,
            protocolFeePercentage,
            poolCreatorFeePercentage,
            true
        );
    }

    function testSwapWithCreatorFee_Fuzz(
        uint256 amountToSwap,
        uint64 swapFeePercentage,
        uint64 protocolFeePercentage,
        uint64 poolCreatorFeePercentage
    ) public {
        (amountToSwap, swapFeePercentage, protocolFeePercentage, poolCreatorFeePercentage) = _bindFuzzTestAmounts(
            amountToSwap,
            swapFeePercentage,
            protocolFeePercentage,
            poolCreatorFeePercentage
        );

        _swapExactInWithFees(
            address(pool),
            usdc,
            dai,
            amountToSwap,
            swapFeePercentage,
            protocolFeePercentage,
            poolCreatorFeePercentage,
            false
        );
    }

    function testProtocolFeeExemptSwapWithCreatorFee_Fuzz(
        uint256 amountToSwap,
        uint64 swapFeePercentage,
        uint64 protocolFeePercentage,
        uint64 poolCreatorFeePercentage
    ) public {
        (amountToSwap, swapFeePercentage, protocolFeePercentage, poolCreatorFeePercentage) = _bindFuzzTestAmounts(
            amountToSwap,
            swapFeePercentage,
            protocolFeePercentage,
            poolCreatorFeePercentage
        );

        _swapExactInWithFees(
            address(exemptPool),
            usdc,
            dai,
            amountToSwap,
            swapFeePercentage,
            protocolFeePercentage,
            poolCreatorFeePercentage,
            false
        );
    }

    function _bindFuzzTestAmounts(
        uint256 amountToSwap,
        uint64 swapFeePercentage,
        uint64 protocolFeePercentage,
        uint64 poolCreatorFeePercentage
    ) private view returns (uint256, uint64, uint64, uint64) {
        return (
            bound(amountToSwap, _defaultAmountToSwap, defaultAmount / 2),
            // 0 to 10%
            (bound(swapFeePercentage, 0, 1e17 / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR).toUint64(),
            // 0 to 50%
            (bound(protocolFeePercentage, 0, 5e17 / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR).toUint64(),
            // 0 to 100%
            (bound(poolCreatorFeePercentage, 0, 1e18 / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR).toUint64()
        );
    }

    function testCollectPoolCreatorFee__Fuzz(
        uint256 amountToSwap,
        uint64 swapFeePercentage,
        uint64 protocolFeePercentage,
        uint64 poolCreatorFeePercentage
    ) public {
        amountToSwap = bound(amountToSwap, _defaultAmountToSwap, defaultAmount / 2);
        // 0 to 10%
        swapFeePercentage = (bound(swapFeePercentage, 0, 1e17 / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR).toUint64();
        // 0 to 50%
        protocolFeePercentage = (bound(protocolFeePercentage, 0, 5e17 / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR)
            .toUint64();
        // 0 to 100%
        poolCreatorFeePercentage = (bound(poolCreatorFeePercentage, 0, 1e18 / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR)
            .toUint64();

        uint256 lpBalanceDaiBefore = dai.balanceOf(address(lp));

        uint256 chargedCreatorFees = _swapExactInWithFees(
            address(pool),
            usdc,
            dai,
            amountToSwap,
            swapFeePercentage,
            protocolFeePercentage,
            poolCreatorFeePercentage,
            false
        );

        vault.collectPoolCreatorFees(address(pool));
        assertEq(
            vault.getPoolCreatorFees(address(pool), dai),
            0,
            "creatorFees in the vault should be 0 after fee collected"
        );

        uint256 lpBalanceDaiAfter = dai.balanceOf(address(lp));
        assertEq(
            lpBalanceDaiAfter - lpBalanceDaiBefore,
            chargedCreatorFees,
            "LP (poolCreator) tokenOut balance should increase by chargedCreatorFees after fee collected"
        );
    }

    /// @dev Avoid "stack too deep"
    struct SwapTestLocals {
        uint256 totalFees;
        uint256 protocolFees;
        uint256 lpFees;
        uint256 aliceTokenInBalanceBefore;
        uint256 aliceTokenOutBalanceBefore;
        uint256 protocolTokenInFeesBefore;
        uint256 protocolTokenOutFeesBefore;
        uint256 creatorTokenInFeesBefore;
        uint256 creatorTokenOutFeesBefore;
    }

    function _swapExactInWithFees(
        address targetPool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        uint256 swapFeePercentage,
        uint64 protocolFeePercentage,
        uint256 creatorFeePercentage,
        bool shouldSnapSwap
    ) private returns (uint256 chargedCreatorFee) {
        SwapTestLocals memory vars;

        setProtocolSwapFeePercentage(protocolFeePercentage);
        // Must set on the specific pool
        _setSwapFeePercentage(targetPool, swapFeePercentage);
        vm.prank(lp);
        vault.setPoolCreatorFeePercentage(targetPool, creatorFeePercentage);

        // totalFees = amountIn * swapFee%
        vars.totalFees = amountIn.mulUp(swapFeePercentage);

        bool isExemptFromProtocolFee = targetPool == address(exemptPool);

        // protocolFees = totalFees * protocolFee% (or 0, if exempt)
        vars.protocolFees = isExemptFromProtocolFee ? 0 : vars.totalFees.mulUp(protocolFeePercentage);

        // creatorAndLPFees = totalFees - protocolFees
        // creatorFees = creatorAndLPFees * creatorFee%
        chargedCreatorFee = (vars.totalFees - vars.protocolFees).mulUp(creatorFeePercentage);

        vars.lpFees = (vars.totalFees - vars.protocolFees).mulUp(FixedPoint.ONE - creatorFeePercentage);

        // Get swap user (alice) balances before transfer
        vars.aliceTokenInBalanceBefore = tokenIn.balanceOf(address(alice));
        vars.aliceTokenOutBalanceBefore = tokenOut.balanceOf(address(alice));

        // Get protocol fees before transfer
        vars.protocolTokenInFeesBefore = vault.getProtocolFees(address(tokenIn));
        vars.protocolTokenOutFeesBefore = vault.getProtocolFees(address(tokenOut));

        // Get creator fees before transfer
        vars.creatorTokenInFeesBefore = vault.getPoolCreatorFees(targetPool, tokenIn);
        vars.creatorTokenOutFeesBefore = vault.getPoolCreatorFees(targetPool, tokenOut);

        uint256[] memory liveBalancesBefore = vault.getLastLiveBalances(targetPool);

        vm.prank(alice);
        if (shouldSnapSwap) {
            if (isExemptFromProtocolFee) {
                snapStart("swapWithOnlyCreatorFee");
            } else {
                snapStart("swapWithCreatorFee");
            }
        }
        router.swapSingleTokenExactIn(targetPool, tokenIn, tokenOut, amountIn, 0, MAX_UINT256, false, bytes(""));
        if (shouldSnapSwap) {
            snapEnd();
        }

        // Check swap user (alice) after transfer
        assertEq(
            tokenIn.balanceOf(address(alice)),
            vars.aliceTokenInBalanceBefore - amountIn,
            "Alice should pay amountIn after swap"
        );
        // amountIn = amountOut, since the rate is 1 and test pool is linear.
        assertEq(
            tokenOut.balanceOf(address(alice)),
            vars.aliceTokenOutBalanceBefore + amountIn - vars.totalFees,
            "Alice should receive amountOut - fees after swap"
        );

        // Check protocol fees after transfer
        assertEq(
            vault.getProtocolFees(address(tokenIn)),
            vars.protocolTokenInFeesBefore,
            "tokenIn protocol fees should not change"
        );
        assertEq(
            vault.getProtocolFees(address(tokenOut)),
            vars.protocolTokenOutFeesBefore + vars.protocolFees,
            "tokenOut protocol fees should increase by vars.protocolFees after swap"
        );

        // Check creator fees after transfer
        assertEq(
            vault.getPoolCreatorFees(targetPool, tokenIn),
            vars.creatorTokenInFeesBefore,
            "tokenIn creator fees should not change"
        );
        assertEq(
            vault.getPoolCreatorFees(targetPool, tokenOut),
            vars.creatorTokenOutFeesBefore + chargedCreatorFee,
            "tokenOut creator fees should increase by chargedCreatorFee after swap"
        );

        // Check protocol + creator fees are always smaller than total fees
        assertLe(
            vars.protocolFees + chargedCreatorFee,
            vars.totalFees,
            "total fees should be >= protocol + creator fees"
        );

        // Check live balances after transfer
        (TokenConfig[] memory tokenConfig, , ) = vault.getPoolTokenInfo(targetPool);
        uint256[] memory liveBalancesAfter = vault.getLastLiveBalances(targetPool);
        for (uint256 i = 0; i < liveBalancesAfter.length; ++i) {
            if (tokenConfig[i].token == tokenIn) {
                assertEq(
                    liveBalancesBefore[i] + amountIn,
                    liveBalancesAfter[i],
                    "Live Balance for tokenIn does not match after swap"
                );
            } else if (tokenConfig[i].token == tokenOut) {
                // Fees are charged from amountIn, but lpFees stay in the pool
                uint256 expectedLiveBalancesAfter = liveBalancesBefore[i] - amountIn + vars.lpFees;
                // Rounding should always favor the protocol when charging fees. We assert that
                // expectedLiveBalancesAfter >= liveBalancesAfter[i], but difference is not greater than 1
                // to tolerate rounding
                assertLe(
                    expectedLiveBalancesAfter - liveBalancesAfter[i],
                    1,
                    "Live Balance for tokenOut does not match after swap"
                );
            }
        }
    }
}
