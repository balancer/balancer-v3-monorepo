// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { VaultContractsDeployer } from "./utils/VaultContractsDeployer.sol";

import { E2eSwapTest } from "./E2eSwap.t.sol";

contract E2eSwapRateProviderTest is VaultContractsDeployer, E2eSwapTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    RateProviderMock internal rateProviderTokenA;
    RateProviderMock internal rateProviderTokenB;

    function _createPool(address[] memory tokens, string memory label) internal virtual override returns (address) {
        address newPool = factoryMock.createPool("ERC20 Pool", "ERC20POOL");
        vm.label(newPool, label);

        rateProviderTokenA = deployRateProviderMock();
        rateProviderTokenB = deployRateProviderMock();
        // Mock rates, so all tests that keep the rate constant use a rate different than 1.
        rateProviderTokenA.mockRate(5.2453235e18);
        rateProviderTokenB.mockRate(0.4362784e18);

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[tokenAIdx] = IRateProvider(address(rateProviderTokenA));
        rateProviders[tokenBIdx] = IRateProvider(address(rateProviderTokenB));

        factoryMock.registerTestPool(
            newPool,
            vault.buildTokenConfig(tokens.asIERC20(), rateProviders),
            poolHooksContract,
            lp
        );

        return newPool;
    }

    function getRate(IERC20 token) internal view override returns (uint256) {
        if (token == tokenA) {
            return rateProviderTokenA.getRate();
        } else {
            return rateProviderTokenB.getRate();
        }
    }

    function testDoUndoExactInSwapRate__Fuzz(uint256 newRateTokenA, uint256 newRateTokenB) public {
        _setPoolRates(newRateTokenA, newRateTokenB);

        DoUndoLocals memory testLocals;
        uint256 exactAmountIn = maxSwapAmountTokenA;

        testDoUndoExactInBase(exactAmountIn, testLocals);
    }

    function testDoUndoExactInSwapRateComplete__Fuzz(
        uint256 exactAmountIn,
        uint256 poolSwapFeePercentage,
        uint256 liquidityTokenA,
        uint256 liquidityTokenB,
        uint256 newDecimalsTokenA,
        uint256 newDecimalsTokenB,
        uint256 newRateTokenA,
        uint256 newRateTokenB
    ) public {
        _setPoolRates(newRateTokenA, newRateTokenB);

        DoUndoLocals memory testLocals;
        testLocals.shouldTestDecimals = true;
        testLocals.shouldTestLiquidity = true;
        testLocals.shouldTestSwapAmount = true;
        testLocals.shouldTestFee = true;
        testLocals.liquidityTokenA = liquidityTokenA;
        testLocals.liquidityTokenB = liquidityTokenB;
        testLocals.newDecimalsTokenA = newDecimalsTokenA;
        testLocals.newDecimalsTokenB = newDecimalsTokenB;
        testLocals.poolSwapFeePercentage = poolSwapFeePercentage;

        testDoUndoExactInBase(exactAmountIn, testLocals);
    }

    function testDoUndoExactOutSwapRate__Fuzz(uint256 newRateTokenA, uint256 newRateTokenB) public {
        _setPoolRates(newRateTokenA, newRateTokenB);

        DoUndoLocals memory testLocals;
        uint256 exactAmountOut = maxSwapAmountTokenB;

        testDoUndoExactOutBase(exactAmountOut, testLocals);
    }

    function testDoUndoExactOutSwapRateComplete__Fuzz(
        uint256 exactAmountOut,
        uint256 poolSwapFeePercentage,
        uint256 liquidityTokenA,
        uint256 liquidityTokenB,
        uint256 newDecimalsTokenA,
        uint256 newDecimalsTokenB,
        uint256 newRateTokenA,
        uint256 newRateTokenB
    ) public {
        _setPoolRates(newRateTokenA, newRateTokenB);

        DoUndoLocals memory testLocals;
        testLocals.shouldTestDecimals = true;
        testLocals.shouldTestLiquidity = true;
        testLocals.shouldTestSwapAmount = true;
        testLocals.shouldTestFee = true;
        testLocals.liquidityTokenA = liquidityTokenA;
        testLocals.liquidityTokenB = liquidityTokenB;
        testLocals.newDecimalsTokenA = newDecimalsTokenA;
        testLocals.newDecimalsTokenB = newDecimalsTokenB;
        testLocals.poolSwapFeePercentage = poolSwapFeePercentage;

        testDoUndoExactOutBase(exactAmountOut, testLocals);
    }

    function _setPoolRates(uint256 newRateTokenA, uint256 newRateTokenB) private {
        // Since the rate is an 18 decimals number, it ranges from 0.01 to 10k.
        newRateTokenA = bound(newRateTokenA, 1e16, 1e22);
        newRateTokenB = bound(newRateTokenB, 1e16, 1e22);

        rateProviderTokenA.mockRate(newRateTokenA);
        rateProviderTokenB.mockRate(newRateTokenB);

        // PoolInitAmounts and pool initial balances depend on the rate.
        setPoolInitAmounts();
        setPoolBalances(poolInitAmountTokenA, poolInitAmountTokenB);

        // Min and Max swap amounts depends on the decimals of each token, so a recalculation is needed.
        calculateMinAndMaxSwapAmounts();
    }
}
