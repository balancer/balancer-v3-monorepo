// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { VaultSwapParams, SwapKind, PoolSwapParams, Rounding, TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { PoolFactoryMock } from "../../../contracts/test/PoolFactoryMock.sol";
import { RateProviderMock } from "../../../contracts/test/RateProviderMock.sol";
import { BalancerPoolToken } from "../../../contracts/BalancerPoolToken.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

/**
 * @notice Regression test: the Vault passes `balancesScaled18` into `IBasePool.onSwap` that correspond to
 *         raw balances scaled with `toScaled18ApplyRateRoundDown` (i.e., no "11.9 -> 11" style truncation).
 *
 * @dev This is intentionally Vault-level (not a math PoC): it asserts the *actual calldata* a pool receives.
 */
contract VaultSwapBalanceLoadRoundingTest is BaseVaultTest {
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;

    // Pool that records the swap params it receives from the Vault.
    RecordingPool internal recordingPool;

    // Use distinct rate providers so this test also catches token<->rate misalignment after sorting.
    RateProviderMock internal daiRateProvider;
    RateProviderMock internal usdcRateProvider;

    function onAfterDeployMainContracts() internal override {
        // BaseVaultTest does not initialize `rateProvider`, but this test relies on it for WITH_RATE tokens.
        // Deploy two independent providers to ensure rates stay correctly aligned with tokens even after sorting.
        daiRateProvider = deployRateProviderMock();
        usdcRateProvider = deployRateProviderMock();

        vm.label(address(daiRateProvider), "daiRateProvider");
        vm.label(address(usdcRateProvider), "usdcRateProvider");

        // Keep BaseVaultTest's `rateProvider` non-zero for any inherited helpers that assume it exists.
        rateProvider = daiRateProvider;
    }

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "Recording Pool";
        string memory symbol = "REC";

        recordingPool = new RecordingPool(IVault(address(vault)), name, symbol);
        newPool = address(recordingPool);
        vm.label(newPool, "recordingPool");

        // Register pool with token rates enabled so rounding paths are exercised.
        IERC20[] memory poolTokens = new IERC20[](2);
        poolTokens[0] = dai;
        poolTokens[1] = usdc;

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        // Must match the array passed in (pre-sorting), since buildTokenConfig will sort tokens and keep alignment.
        rateProviders[0] = IRateProvider(address(daiRateProvider));
        rateProviders[1] = IRateProvider(address(usdcRateProvider));

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(poolTokens, rateProviders);
        PoolFactoryMock(poolFactory).registerTestPool(newPool, tokenConfig, poolHooksContract, lp);

        poolArgs = abi.encode(vault, name, symbol);
    }

    /**
     * @dev Called by the Vault as part of `unlock`. In this context, `msg.sender` is the Vault.
     */
    function doVaultSwap(VaultSwapParams calldata params) external {
        (, , uint256 amountOut) = IVault(msg.sender).swap(params);

        // Clear all token deltas so `unlock` doesn't revert with BalanceNotSettled.
        // We do this generically (instead of assuming exact debt amounts) so the test is robust to fee changes.
        _clearTokenDelta(IVault(msg.sender), IERC20(params.tokenIn));
        _clearTokenDelta(IVault(msg.sender), IERC20(params.tokenOut));

        // Keep compiler happy: amountOut isn't used directly now, but it's part of the behavior under test.
        amountOut;
    }

    function _clearTokenDelta(IVault vault_, IERC20 token) private {
        // The transient delta is stored in the VaultExtension and can only be read via delegatecall through the Vault.
        IVaultExtension ext = IVaultExtension(address(vault_));

        // Iterate a few times in case settle/sendTo changes the delta in multiple steps.
        for (uint256 i = 0; i < 4; ++i) {
            int256 delta = ext.getTokenDelta(token);
            if (delta == 0) return;

            if (delta > 0) {
                // Positive delta = debt owed to the Vault. Pay it, then settle to convert reserves into credit.
                uint256 debt = uint256(delta);
                require(token.balanceOf(address(this)) >= debt, "insufficient balance to repay debt");
                token.transfer(address(vault_), debt);
                vault_.settle(token, debt);
            } else {
                // Negative delta = credit owed to the caller. Consume it by withdrawing tokens.
                uint256 credit = uint256(-delta);
                vault_.sendTo(token, address(this), credit);
            }
        }

        // If we reach here, something is off (and unlock would revert anyway).
        require(ext.getTokenDelta(token) == 0, "token delta not cleared");
    }

    function testSwapBalancesPassedToPoolAreRoundDownScaled() public {
        // Choose non-1 rates so mulUp vs mulDown can differ, even for "dusty" balances.
        uint256 rateDai = 1234567890123456789;
        uint256 rateUsdc = 1987654321098765432;
        daiRateProvider.mockRate(rateDai);
        usdcRateProvider.mockRate(rateUsdc);
        assertEq(daiRateProvider.getRate(), rateDai, "DAI rateProvider mock not applied");
        assertEq(usdcRateProvider.getRate(), rateUsdc, "USDC rateProvider mock not applied");

        // Make raw balances "dusty" (not multiples of token decimals) so the ceil/floor branch can differ by 1.
        // NOTE: VaultExtension methods are only callable via delegatecall through the Vault proxy.
        IVaultExtension ext = IVaultExtension(address(vault));
        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = ext.getPoolTokenInfo(pool);
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (tokens[i] == dai) {
                // 18 decimals
                balancesRaw[i] = 1_000e18 + 1;
            } else if (tokens[i] == usdc) {
                // NOTE: In this test harness, "USDC" is an 18-decimal test token (see BaseMedusaTest/VaultBufferUnit).
                // We keep values "dusty" relative to 1e18 to exercise rounding boundaries reliably.
                balancesRaw[i] = 2_000e18 + 3;
            } else {
                revert("unexpected token in pool");
            }
        }
        vault.manualSetPoolTokensAndBalances(pool, tokens, balancesRaw, balancesRaw);

        // Compute the expected balancesScaled18 exactly as the Vault should load them for swap math.
        (uint256[] memory scalingFactors, ) = ext.getPoolTokenRates(pool);
        uint256[] memory expectedDown = new uint256[](balancesRaw.length);
        uint256[] memory expectedUp = new uint256[](balancesRaw.length);
        bool hasUpDownDifference = false;
        for (uint256 i = 0; i < balancesRaw.length; ++i) {
            uint256 tokenRate;
            if (tokens[i] == dai) {
                tokenRate = rateDai;
            } else {
                // usdc
                tokenRate = rateUsdc;
            }

            expectedDown[i] = ScalingHelpers.toScaled18ApplyRateRoundDown(balancesRaw[i], scalingFactors[i], tokenRate);
            expectedUp[i] = ScalingHelpers.toScaled18ApplyRateRoundUp(balancesRaw[i], scalingFactors[i], tokenRate);
            if (expectedUp[i] != expectedDown[i]) {
                hasUpDownDifference = true;
            }
        }
        // Guard against a "green for both implementations" test: we want at least one token where round-up differs.
        // If this fails, it indicates the chosen balances/rates didn't create a rounding boundary (test setup issue).
        require(hasUpDownDifference, "test precondition failed: roundUp == roundDown for all tokens");

        // Perform a swap; our RecordingPool captures the calldata.
        // Use a fixed direction to avoid address-order dependent behavior.
        IERC20 tokenIn = dai;
        IERC20 tokenOut = usdc;

        // Fund this contract so it can settle the swap during `unlock`.
        deal(address(tokenIn), address(this), 10e18);
        VaultSwapParams memory params = VaultSwapParams({
            kind: SwapKind.EXACT_IN,
            pool: pool,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountGivenRaw: 1e18,
            limitRaw: 0,
            userData: bytes("")
        });
        vault.unlock(abi.encodeCall(this.doVaultSwap, (params)));

        // Assert pool received balances that match Vault's ROUND_DOWN scaling.
        uint256[] memory got = recordingPool.getLastBalancesScaled18();
        assertEq(got.length, expectedDown.length, "unexpected balances length");
        for (uint256 i = 0; i < got.length; ++i) {
            assertEq(got[i], expectedDown[i], "balancesScaled18 not round-down scaled");
            // If this index would differ under round-up scaling, assert we didn't accidentally round up.
            if (expectedUp[i] != expectedDown[i]) {
                assertTrue(got[i] != expectedUp[i], "balancesScaled18 unexpectedly matches round-up scaling");
            }
        }

        // Extra sanity checks: ensure we actually captured the intended call shape (kind + indices).
        assertEq(uint8(recordingPool.lastKind()), uint8(SwapKind.EXACT_IN), "unexpected swap kind");
        (uint256 expectedIndexIn, uint256 expectedIndexOut) = _findTokenIndices(tokens, tokenIn, tokenOut);
        assertEq(recordingPool.lastIndexIn(), expectedIndexIn, "unexpected indexIn");
        assertEq(recordingPool.lastIndexOut(), expectedIndexOut, "unexpected indexOut");
    }

    function _findTokenIndices(
        IERC20[] memory tokens,
        IERC20 tokenIn,
        IERC20 tokenOut
    ) private pure returns (uint256 indexIn, uint256 indexOut) {
        bool foundIn = false;
        bool foundOut = false;
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (tokens[i] == tokenIn) {
                indexIn = i;
                foundIn = true;
            } else if (tokens[i] == tokenOut) {
                indexOut = i;
                foundOut = true;
            }
        }
        require(foundIn && foundOut, "token indices not found");
    }
}

contract RecordingPool is IBasePool, IPoolLiquidity, BalancerPoolToken {
    using FixedPoint for uint256;

    uint256[] private _lastBalancesScaled18;
    SwapKind public lastKind;
    uint256 public lastAmountGivenScaled18;
    uint256 public lastIndexIn;
    uint256 public lastIndexOut;

    constructor(IVault vault, string memory name, string memory symbol) BalancerPoolToken(vault, name, symbol) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getLastBalancesScaled18() external view returns (uint256[] memory) {
        return _lastBalancesScaled18;
    }

    function onSwap(PoolSwapParams calldata params) external override returns (uint256 amountCalculated) {
        delete _lastBalancesScaled18;
        for (uint256 i = 0; i < params.balancesScaled18.length; ++i) {
            _lastBalancesScaled18.push(params.balancesScaled18[i]);
        }
        lastKind = params.kind;
        lastAmountGivenScaled18 = params.amountGivenScaled18;
        lastIndexIn = params.indexIn;
        lastIndexOut = params.indexOut;

        // Return 0 so this test doesn't depend on Vault reserves for tokenOut transfers.
        return 0;
    }

    function computeInvariant(uint256[] memory balances, Rounding) public pure returns (uint256) {
        uint256 invariant;
        for (uint256 i = 0; i < balances.length; ++i) {
            invariant += balances[i];
        }
        return invariant;
    }

    function computeBalance(
        uint256[] memory balances,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external pure returns (uint256 newBalance) {
        uint256 invariant = computeInvariant(balances, Rounding.ROUND_DOWN);
        return (balances[tokenInIndex] + invariant.mulDown(invariantRatio)) - invariant;
    }

    function onAddLiquidityCustom(
        address,
        uint256[] memory maxAmountsInScaled18,
        uint256 minBptAmountOut,
        uint256[] memory,
        bytes memory userData
    ) external pure override returns (uint256[] memory, uint256, uint256[] memory, bytes memory) {
        return (maxAmountsInScaled18, minBptAmountOut, new uint256[](maxAmountsInScaled18.length), userData);
    }

    function onRemoveLiquidityCustom(
        address,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        uint256[] memory,
        bytes memory userData
    ) external pure override returns (uint256, uint256[] memory, uint256[] memory, bytes memory) {
        return (maxBptAmountIn, minAmountsOut, new uint256[](minAmountsOut.length), userData);
    }

    /// @dev Even though pools do not handle scaling, we still need this for the tests.
    function getDecimalScalingFactors() external view returns (uint256[] memory scalingFactors) {
        (scalingFactors, ) = _vault.getPoolTokenRates(address(this));
    }

    function getMinimumSwapFeePercentage() external pure override returns (uint256) {
        return 0;
    }

    function getMaximumSwapFeePercentage() external pure override returns (uint256) {
        return FixedPoint.ONE;
    }

    function getMinimumInvariantRatio() external pure override returns (uint256) {
        return 0;
    }

    function getMaximumInvariantRatio() external pure override returns (uint256) {
        return 1e40;
    }
}

