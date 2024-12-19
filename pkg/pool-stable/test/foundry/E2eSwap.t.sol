// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { ProtocolFeeControllerMock } from "@balancer-labs/v3-vault/contracts/test/ProtocolFeeControllerMock.sol";
import { E2eSwapTest } from "@balancer-labs/v3-vault/test/foundry/E2eSwap.t.sol";

import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../contracts/StablePool.sol";
import { StablePoolContractsDeployer } from "./utils/StablePoolContractsDeployer.sol";

contract E2eSwapStableTest is E2eSwapTest, StablePoolContractsDeployer {
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    uint256 internal constant DEFAULT_SWAP_FEE = 1e16; // 1%
    uint256 internal constant DEFAULT_AMP_FACTOR = 200;

    function setUp() public override {
        E2eSwapTest.setUp();
    }

    function setUpVariables() internal override {
        sender = lp;
        poolCreator = lp;

        // 0.0001% max swap fee.
        minPoolSwapFeePercentage = 1e12;
        // 10% max swap fee.
        maxPoolSwapFeePercentage = 10e16;
    }

    function calculateMinAndMaxSwapAmounts() internal virtual override {
        uint256 rateTokenA = getRate(tokenA);
        uint256 rateTokenB = getRate(tokenB);

        // The vault does not allow trade amounts (amountGivenScaled18 or amountCalculatedScaled18) to be less than
        // MIN_TRADE_AMOUNT. For "linear pools" (PoolMock), amountGivenScaled18 and amountCalculatedScaled18 are
        // the same. So, minAmountGivenScaled18 > MIN_TRADE_AMOUNT. To derive the formula below, note that
        // `amountGivenRaw = amountGivenScaled18/(rateToken * scalingFactor)`. There's an adjustment for stable math
        // in the following steps.
        uint256 tokenAMinTradeAmount = PRODUCTION_MIN_TRADE_AMOUNT.divUp(rateTokenA).mulUp(10 ** decimalsTokenA);
        uint256 tokenBMinTradeAmount = PRODUCTION_MIN_TRADE_AMOUNT.divUp(rateTokenB).mulUp(10 ** decimalsTokenB);

        // Also, since we undo the operation (reverse swap with the output of the first swap), amountCalculatedRaw
        // cannot be 0. Considering that amountCalculated is tokenB, and amountGiven is tokenA:
        // 1) amountCalculatedRaw > 0
        // 2) amountCalculatedRaw = amountCalculatedScaled18 * 10^(decimalsB) / (rateB * 10^18)
        // 3) amountCalculatedScaled18 = amountGivenScaled18 // Linear math, there's a factor to stable math
        // 4) amountGivenScaled18 = amountGivenRaw * rateA * 10^18 / 10^(decimalsA)
        // Using the four formulas above, we determine that:
        // amountCalculatedRaw > rateB * 10^(decimalsA) / (rateA * 10^(decimalsB))
        uint256 tokenACalculatedNotZero = (rateTokenB * (10 ** decimalsTokenA)) / (rateTokenA * (10 ** decimalsTokenB));
        uint256 tokenBCalculatedNotZero = (rateTokenA * (10 ** decimalsTokenB)) / (rateTokenB * (10 ** decimalsTokenA));

        // Use the larger of the two values above to calculate the minSwapAmount. Also, multiply by 10 to account for
        // swap fees and compensate for rate rounding issues.
        uint256 mathFactor = 10;
        minSwapAmountTokenA = (
            tokenAMinTradeAmount > tokenACalculatedNotZero
                ? mathFactor * tokenAMinTradeAmount
                : mathFactor * tokenACalculatedNotZero
        );
        minSwapAmountTokenB = (
            tokenBMinTradeAmount > tokenBCalculatedNotZero
                ? mathFactor * tokenBMinTradeAmount
                : mathFactor * tokenBCalculatedNotZero
        );

        // 50% of pool init amount to make sure LP has enough tokens to pay for the swap in case of EXACT_OUT.
        maxSwapAmountTokenA = poolInitAmountTokenA.mulDown(50e16);
        maxSwapAmountTokenB = poolInitAmountTokenB.mulDown(50e16);
    }

    /// @notice Overrides BaseVaultTest _createPool(). This pool is used by E2eSwapTest tests.
    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "Stable Pool";
        string memory symbol = "STABLE";
        string memory poolVersion = "Pool v1";

        StablePoolFactory factory = deployStablePoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            poolVersion
        );
        PoolRoleAccounts memory roleAccounts;

        // Allow pools created by `factory` to use poolHooksMock hooks.
        PoolHooksMock(poolHooksContract()).allowFactory(address(factory));

        newPool = factory.create(
            name,
            symbol,
            vault.buildTokenConfig(tokens.asIERC20()),
            DEFAULT_AMP_FACTOR,
            roleAccounts,
            DEFAULT_SWAP_FEE, // 1% swap fee, but test will override it
            poolHooksContract(),
            false, // Do not enable donations
            false, // Do not disable unbalanced add/remove liquidity
            ZERO_BYTES32
        );
        vm.label(address(newPool), label);

        // Cannot set the pool creator directly on a standard Balancer stable pool factory.
        vault.manualSetPoolCreator(address(newPool), lp);

        ProtocolFeeControllerMock feeController = ProtocolFeeControllerMock(address(vault.getProtocolFeeController()));
        feeController.manualSetPoolCreator(address(newPool), lp);

        poolArgs = abi.encode(
            StablePool.NewPoolParams({
                name: name,
                symbol: symbol,
                amplificationParameter: DEFAULT_AMP_FACTOR,
                version: poolVersion
            }),
            vault
        );
    }
}
