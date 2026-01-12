// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IStablePool } from "@balancer-labs/v3-interfaces/contracts/pool-stable/IStablePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { RateProviderMock } from "@balancer-labs/v3-vault/contracts/test/RateProviderMock.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { BasePoolMath } from "@balancer-labs/v3-vault/contracts/BasePoolMath.sol";

import { VaultContractsDeployer } from "@balancer-labs/v3-vault/test/foundry/utils/VaultContractsDeployer.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StablePoolContractsDeployer } from "./utils/StablePoolContractsDeployer.sol";
import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../contracts/StablePool.sol";

contract E2EImbalanceTest is StablePoolContractsDeployer, VaultContractsDeployer, BaseVaultTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;
    using ArrayHelpers for *;

    uint256 internal constant TOKEN_IN = 0;
    uint256 internal constant TOKEN_OUT = 1;
    uint256 internal constant DEFAULT_AMOUNT_IN_RATIO = 400e18; // 200x
    uint256 internal constant DEFAULT_AMOUNT_OUT_RATIO = 0.999999e18; // 0.999x
    uint256 internal constant DEFAULT_AMP_FACTOR = 4000 * StableMath.AMP_PRECISION;
    uint256 internal constant MAX_IMBALANCE_RATIO = 10_000e18;
    string internal constant POOL_VERSION = "Pool v1";

    function setUp() public override {
        setDefaultAccountBalance(MAX_UINT128);
        super.setUp();
        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);
    }

    function createPoolFactory() internal override returns (address) {
        return address(deployStablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", POOL_VERSION));
    }

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "ERC20 Pool";
        string memory symbol = "ERC20POOL";

        TokenConfig[] memory tokenConfigs = new TokenConfig[](2);
        IERC20[] memory sortedTokens = InputHelpers.sortTokens(
            [address(usdc6Decimals), address(wbtc8Decimals)].toMemoryArray().asIERC20()
        );
        for (uint256 i = 0; i < sortedTokens.length; i++) {
            tokenConfigs[i].token = sortedTokens[i];
            tokenConfigs[i].tokenType = TokenType.WITH_RATE;

            RateProviderMock rateProvider = new RateProviderMock();
            rateProvider.mockRate(1e18 + (1 + i) * 1e17);
            tokenConfigs[i].rateProvider = IRateProvider(address(rateProvider));
        }

        PoolRoleAccounts memory roleAccounts;
        roleAccounts.swapFeeManager = alice;

        newPool = StablePoolFactory(poolFactory).create(
            name,
            symbol,
            tokenConfigs,
            DEFAULT_AMP_FACTOR / StableMath.AMP_PRECISION,
            roleAccounts,
            BASE_MIN_SWAP_FEE,
            poolHooksContract,
            false, // Do not enable donations
            false, // Do not disable unbalanced add/remove liquidity
            ZERO_BYTES32
        );

        // poolArgs is used to check pool deployment address with create2.
        poolArgs = abi.encode(
            StablePool.NewPoolParams({
                name: name,
                symbol: symbol,
                amplificationParameter: DEFAULT_AMP_FACTOR / StableMath.AMP_PRECISION,
                version: POOL_VERSION
            }),
            vault
        );
    }

    function testImbalanceSwapExactIn() public {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        PoolData memory poolData = vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_DOWN);
        uint256 amountInRaw = poolData.balancesRaw[TOKEN_IN].mulDown(DEFAULT_AMOUNT_IN_RATIO);
        uint256 amountInScaled18 = _scaleAmountDown(poolData, amountInRaw, TOKEN_IN);

        uint256 amountOutScaled18 = StableMath.computeOutGivenExactIn(
            DEFAULT_AMP_FACTOR,
            poolData.balancesLiveScaled18,
            TOKEN_IN,
            TOKEN_OUT,
            amountInScaled18,
            StableMath.computeInvariant(DEFAULT_AMP_FACTOR, poolData.balancesLiveScaled18)
        );
        poolData.balancesLiveScaled18[TOKEN_IN] += amountInScaled18;
        poolData.balancesLiveScaled18[TOKEN_OUT] -= amountOutScaled18;

        vm.startPrank(alice);
        tokens[TOKEN_IN].transfer(address(vault), amountInRaw);

        vm.expectRevert(StableMath.MaxImbalanceRatioExceeded.selector);
        prepaidRouter.swapSingleTokenExactIn(
            pool,
            tokens[TOKEN_IN],
            tokens[TOKEN_OUT],
            amountInRaw,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function testImbalanceSwapExactOut() public {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        PoolData memory poolData = vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_DOWN);

        uint256 amountOutRaw = poolData.balancesRaw[TOKEN_OUT].mulDown(DEFAULT_AMOUNT_OUT_RATIO);
        uint256 amountOutScaled18 = _scaleAmountUp(poolData, amountOutRaw, TOKEN_OUT);

        uint256 amountInScaled18 = StableMath.computeInGivenExactOut(
            DEFAULT_AMP_FACTOR,
            poolData.balancesLiveScaled18,
            TOKEN_IN,
            TOKEN_OUT,
            amountOutScaled18,
            StableMath.computeInvariant(DEFAULT_AMP_FACTOR, poolData.balancesLiveScaled18)
        );
        poolData.balancesLiveScaled18[TOKEN_IN] += amountInScaled18;
        poolData.balancesLiveScaled18[TOKEN_OUT] -= amountOutScaled18;

        vm.startPrank(alice);
        tokens[TOKEN_IN].transfer(address(vault), defaultAccountBalance());

        vm.expectRevert(StableMath.MaxImbalanceRatioExceeded.selector);
        prepaidRouter.swapSingleTokenExactOut(
            pool,
            tokens[TOKEN_IN],
            tokens[TOKEN_OUT],
            amountOutRaw,
            defaultAccountBalance(),
            MAX_UINT128,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function testAddLiquidityUnbalanced() public {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        PoolData memory poolData = vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_UP);

        uint256[] memory balancesRaw = poolData.balancesRaw;
        uint256[] memory balancesLiveScaled18 = poolData.balancesLiveScaled18;

        (uint256 higherBalanceIndex, uint256 lowerBalanceIndex) = _findHighAndLowBalanceIndexes(balancesLiveScaled18);
        uint256 higherBalance = balancesRaw[lowerBalanceIndex].mulDown(MAX_IMBALANCE_RATIO);
        uint256 amountRaw = higherBalance - balancesRaw[higherBalanceIndex];
        uint256 amountScaled18 = _scaleAmountDown(poolData, amountRaw, higherBalanceIndex);
        balancesLiveScaled18[higherBalanceIndex] += amountScaled18;

        vm.startPrank(alice);
        uint256[] memory exactAmountsIn = new uint256[](tokens.length);
        exactAmountsIn[higherBalanceIndex] = amountRaw;

        tokens[higherBalanceIndex].transfer(address(vault), exactAmountsIn[higherBalanceIndex]);

        vm.expectRevert(StableMath.MaxImbalanceRatioExceeded.selector);
        prepaidRouter.addLiquidityUnbalanced(pool, exactAmountsIn, 0, false, bytes(""));

        vm.stopPrank();
    }

    function testAddLiquiditySingleTokenExactOut() public {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        PoolData memory poolData = vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_UP);

        (uint256 higherBalanceIndex, ) = _findHighAndLowBalanceIndexes(poolData.balancesLiveScaled18);

        vm.startPrank(alice);

        uint256 iterations = 3;
        IERC20 token = tokens[higherBalanceIndex];

        for (uint256 i = 0; i < iterations; i++) {
            uint256 totalSupply = IERC20(pool).totalSupply();
            uint256 exactBptAmountOut = totalSupply.mulDown(StableMath.MAX_INVARIANT_RATIO) - totalSupply;

            uint256 maxAmountIn = defaultAccountBalance();
            deal(address(token), alice, maxAmountIn);
            token.transfer(address(vault), maxAmountIn);

            bool isLastStep = i == iterations - 1;
            if (isLastStep) {
                PoolData memory newPoolData = vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_UP);

                uint256 newSupply = exactBptAmountOut + totalSupply;
                uint256 invariantRatio = newSupply.divUp(totalSupply);
                uint256 newBalance = StableMath.computeBalance(
                    DEFAULT_AMP_FACTOR,
                    newPoolData.balancesLiveScaled18,
                    StablePool(pool).computeInvariant(newPoolData.balancesLiveScaled18, Rounding.ROUND_UP).mulUp(
                        invariantRatio
                    ),
                    higherBalanceIndex
                );
                newPoolData.balancesLiveScaled18[higherBalanceIndex] = newBalance;

                vm.expectRevert(StableMath.MaxImbalanceRatioExceeded.selector);
                prepaidRouter.addLiquiditySingleTokenExactOut(
                    pool,
                    token,
                    maxAmountIn,
                    exactBptAmountOut,
                    false,
                    bytes("")
                );
            } else {
                // Increase balance within allowed invariant ratio
                prepaidRouter.addLiquiditySingleTokenExactOut(
                    pool,
                    token,
                    maxAmountIn,
                    exactBptAmountOut,
                    false,
                    bytes("")
                );
            }
        }

        vm.stopPrank();
    }

    function testRemoveLiquiditySingleTokenExactIn() public {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        PoolData memory poolData = vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_DOWN);

        (, uint256 lowerBalanceIndex) = _findHighAndLowBalanceIndexes(poolData.balancesLiveScaled18);

        vm.startPrank(alice);

        uint256 iterations = 2;
        for (uint256 i = 0; i < iterations; i++) {
            uint256 totalSupply = IERC20(pool).totalSupply();
            uint256 exactBptAmountIn = totalSupply / 5;
            vault.mintERC20(pool, alice, exactBptAmountIn);

            totalSupply = IERC20(pool).totalSupply();

            IERC20 token = tokens[lowerBalanceIndex];
            IERC20(pool).approve(address(prepaidRouter), exactBptAmountIn);

            bool isLastStep = i == iterations - 1;
            if (isLastStep) {
                PoolData memory newPoolData = vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_DOWN);

                // Simulate the balance after removal
                uint256 newSupply = totalSupply - exactBptAmountIn;
                uint256 invariantRatio = newSupply.divUp(totalSupply);
                uint256 newBalance = StableMath.computeBalance(
                    DEFAULT_AMP_FACTOR,
                    newPoolData.balancesLiveScaled18,
                    StablePool(pool).computeInvariant(newPoolData.balancesLiveScaled18, Rounding.ROUND_UP).mulUp(
                        invariantRatio
                    ),
                    lowerBalanceIndex
                );
                newPoolData.balancesLiveScaled18[lowerBalanceIndex] = newBalance;

                vm.expectRevert(StableMath.MaxImbalanceRatioExceeded.selector);
                prepaidRouter.removeLiquiditySingleTokenExactIn(pool, exactBptAmountIn, token, 1, false, bytes(""));
            } else {
                // Decrease balance within allowed invariant ratio
                prepaidRouter.removeLiquiditySingleTokenExactIn(pool, exactBptAmountIn, token, 1, false, bytes(""));
            }
        }

        vm.stopPrank();
    }

    function testRemoveLiquiditySingleTokenExactOut() public {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        PoolData memory poolData = vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_DOWN);

        (, uint256 lowerBalanceIndex) = _findHighAndLowBalanceIndexes(poolData.balancesLiveScaled18);

        uint256 amountOutRaw = poolData.balancesRaw[lowerBalanceIndex] / 6;

        vm.startPrank(alice);

        uint256 iterations = 6;
        for (uint256 i = 0; i < iterations; i++) {
            uint256 totalSupply = IERC20(pool).totalSupply();
            uint256 exactBptAmountIn = totalSupply;

            vault.mintERC20(pool, alice, exactBptAmountIn);
            totalSupply = IERC20(pool).totalSupply();

            IERC20 token = tokens[lowerBalanceIndex];
            IERC20(pool).approve(address(prepaidRouter), exactBptAmountIn);

            bool isLastStep = i == iterations - 1;
            if (isLastStep) {
                PoolData memory newPoolData = vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_DOWN);

                for (uint256 j = 0; j < newPoolData.balancesLiveScaled18.length; ++j) {
                    newPoolData.balancesLiveScaled18[j] -= 1;
                }
                uint256 amountOutScaled18 = _scaleAmountUpRateDown(newPoolData, amountOutRaw, lowerBalanceIndex);

                newPoolData.balancesLiveScaled18[lowerBalanceIndex] -= amountOutScaled18;

                vm.expectRevert(StableMath.MaxImbalanceRatioExceeded.selector);
                prepaidRouter.removeLiquiditySingleTokenExactOut(
                    pool,
                    exactBptAmountIn,
                    token,
                    amountOutRaw,
                    false,
                    bytes("")
                );
            } else {
                // Decrease balance within allowed invariant ratio
                prepaidRouter.removeLiquiditySingleTokenExactOut(
                    pool,
                    exactBptAmountIn,
                    token,
                    amountOutRaw,
                    false,
                    bytes("")
                );
            }
        }

        vm.stopPrank();
    }

    // Private helper functions
    function _findHighAndLowBalanceIndexes(
        uint256[] memory balancesScaled18
    ) private pure returns (uint256 higherBalanceIndex, uint256 lowerBalanceIndex) {
        higherBalanceIndex = 0;
        lowerBalanceIndex = 1;
        for (uint256 i = 0; i < balancesScaled18.length; i++) {
            if (balancesScaled18[i] > balancesScaled18[higherBalanceIndex]) {
                higherBalanceIndex = i;
            }

            if (balancesScaled18[i] < balancesScaled18[lowerBalanceIndex]) {
                lowerBalanceIndex = i;
            }
        }
    }

    function _scaleAmountUp(
        PoolData memory poolData,
        uint256 amountInRaw,
        uint256 index
    ) private pure returns (uint256 amountInScaled18) {
        amountInScaled18 = amountInRaw.toScaled18ApplyRateRoundUp(
            poolData.decimalScalingFactors[index],
            poolData.tokenRates[index].computeRateRoundUp()
        );
    }

    function _scaleAmountUpRateDown(
        PoolData memory poolData,
        uint256 amountInRaw,
        uint256 index
    ) private pure returns (uint256 amountInScaled18) {
        amountInScaled18 = amountInRaw.toScaled18ApplyRateRoundUp(
            poolData.decimalScalingFactors[index],
            poolData.tokenRates[index]
        );
    }

    function _scaleAmountDown(
        PoolData memory poolData,
        uint256 amountInRaw,
        uint256 index
    ) private pure returns (uint256 amountInScaled18) {
        amountInScaled18 = amountInRaw.toScaled18ApplyRateRoundDown(
            poolData.decimalScalingFactors[index],
            poolData.tokenRates[index]
        );
    }
}
