// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseMedusaTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseMedusaTest.sol";

import { GyroECLPPoolFactory } from "../../../contracts/GyroECLPPoolFactory.sol";
import { GyroECLPMath } from "../../../contracts/lib/GyroECLPMath.sol";

/**
 * @title SwapECLP Medusa Fuzz Test
 * @notice High-signal adversarial fuzz tests for Gyro ECLP swaps (Vault + Router integration).
 * @dev This file is intentionally *not* pure-math coverage (see `test/foundry/improvements/*ECLP*.t.sol`).
 * Focus:
 *  - Swap integration correctness: token deltas match returned amounts
 *  - Revert-safety: failed swaps must not mutate pool/user state
 *  - Expected revert domain: large trades should only fail due to ECLP asset bounds
 *  - No-arbitrage: round-trip swaps should never profit the trader (dust-only tolerance)
 *  - LP safety: BPT rate should not decrease after successful swaps (allow tiny eps)
 *  - Price safety: computed spot price remains within [alpha, beta]
 */
contract SwapECLPMedusa is BaseMedusaTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    error ZeroAmountOut();
    error ZeroAmountIn();
    error BptRateDecreased(uint256 currentRate, uint256 lastKnownRate, uint256 minAllowed);
    error RoundTripProfitStrict(uint256 finalAmount, uint256 maxAllowed, uint256 amountIn);
    error RevertedWithoutData();
    error UnexpectedRevertSelector(bytes4 selector);
    error TokenBalanceDidNotDecrease(address token, uint256 beforeBal, uint256 afterBal, uint256 expectedDelta);
    error TokenBalanceDidNotIncrease(address token, uint256 beforeBal, uint256 afterBal, uint256 expectedDelta);
    error PoolBalanceDidNotChangeByExpectedAmount(uint256 tokenIndex, uint256 beforeBal, uint256 afterBal, uint256 expectedDelta);
    error PoolBalanceDeltaMismatch(uint256 tokenIndex);
    error SpotPriceOutOfBounds(uint256 spotPrice, uint256 alpha, uint256 beta);

    // ECLP pools require a consistent (params, derivedParams) pair; derived params are typically computed off-chain.
    // These constants are a known-good mainnet fixture (see `test/foundry/utils/GyroEclpPoolDeployer.sol`).
    int256 internal constant PARAMS_ALPHA = 998502246630054917;
    int256 internal constant PARAMS_BETA = 1000200040008001600;
    int256 internal constant PARAMS_C = 707106781186547524;
    int256 internal constant PARAMS_S = 707106781186547524;
    int256 internal constant PARAMS_LAMBDA = 4000000000000000000000;

    int256 internal constant TAU_ALPHA_X = -94861212813096057289512505574275160547;
    int256 internal constant TAU_ALPHA_Y = 31644119574235279926451292677567331630;
    int256 internal constant TAU_BETA_X = 37142269533113549537591131345643981951;
    int256 internal constant TAU_BETA_Y = 92846388265400743995957747409218517601;
    int256 internal constant DERIVED_U = 66001741173104803338721745994955553010;
    int256 internal constant DERIVED_V = 62245253919818011890633399060291020887;
    int256 internal constant DERIVED_W = 30601134345582732000058913853921008022;
    int256 internal constant DERIVED_Z = -28859471639991253843240999485797747790;
    int256 internal constant DERIVED_DSQ = 99999999999999999886624093342106115200;

    // Limits
    // NOTE: token decimals differ (DAI 18, USDC 6). We set per-token minimums to avoid "rounds to zero" domains.
    uint256 internal constant MIN_SWAP_USDC = 1e6; // 1 USDC
    uint256 internal constant MIN_SWAP_DAI = 1e12; // 1e-6 DAI
    uint256 internal constant MAX_SWAP_RATIO_EXACT_IN = 20e16; // 20% of balance per swap
    // Exact-out is more failure-prone near bounds; keep it smaller for non-vacuous fuzzing campaigns.
    uint256 internal constant MAX_SWAP_RATIO_EXACT_OUT = 10e16; // 10% of out-balance per exact-out request
    // Round trips require two successful legs; keep amounts smaller to reduce "mostly reverting" campaigns.
    uint256 internal constant MAX_SWAP_RATIO_ROUND_TRIP = 5e16; // 5% per-leg input

    // Track state
    uint256 internal lastKnownBptRate;

    constructor() BaseMedusaTest() {
        lastKnownBptRate = _getCurrentBptRate();
    }

    /**
     * @notice Override to create an ECLP pool
     */
    function createPool(
        IERC20[] memory tokens,
        uint256[] memory initialBalances
    ) internal override returns (address newPool) {
        GyroECLPPoolFactory factory = new GyroECLPPoolFactory(vault, 365 days, "", "");

        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);

        IGyroECLPPool.EclpParams memory eclpParams = IGyroECLPPool.EclpParams({
            alpha: PARAMS_ALPHA,
            beta: PARAMS_BETA,
            c: PARAMS_C,
            s: PARAMS_S,
            lambda: PARAMS_LAMBDA
        });

        IGyroECLPPool.DerivedEclpParams memory derivedParams = IGyroECLPPool.DerivedEclpParams({
            tauAlpha: IGyroECLPPool.Vector2(TAU_ALPHA_X, TAU_ALPHA_Y),
            tauBeta: IGyroECLPPool.Vector2(TAU_BETA_X, TAU_BETA_Y),
            u: DERIVED_U,
            v: DERIVED_V,
            w: DERIVED_W,
            z: DERIVED_Z,
            dSq: DERIVED_DSQ
        });

        PoolRoleAccounts memory roleAccounts;

        newPool = factory.create(
            "Gyro ECLP Pool",
            "GECLP",
            vault.buildTokenConfig(tokens, rateProviders),
            eclpParams,
            derivedParams,
            roleAccounts,
            1e12,
            address(0),
            false,
            false,
            bytes32("")
        );

        medusa.prank(lp);
        router.initialize(newPool, tokens, initialBalances, 0, false, bytes(""));

        return newPool;
    }

    /**
     * @notice Override to use 2 tokens
     */
    function getTokensAndInitialBalances()
        internal
        override
        returns (IERC20[] memory tokens, uint256[] memory initialBalances)
    {
        tokens = new IERC20[](2);
        tokens[0] = dai;
        tokens[1] = usdc;
        tokens = InputHelpers.sortTokens(tokens);

        initialBalances = new uint256[](2);
        initialBalances[0] = DEFAULT_INITIAL_POOL_BALANCE;
        initialBalances[1] = DEFAULT_INITIAL_POOL_BALANCE;
    }

    /***************************************************************************
                               FUZZ FUNCTIONS
     ***************************************************************************/

    /**
     * @notice Fuzz: Exact input swap token0 -> token1
     */
    function swapExactIn0to1(uint256 amountIn) external {
        (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));

        uint256 minSwap = _minSwap(tokens[0]);
        uint256 maxSwap = balancesBefore[0].mulDown(MAX_SWAP_RATIO_EXACT_IN);
        if (maxSwap < minSwap) return;
        amountIn = _boundLocal(amountIn, minSwap, maxSwap);

        uint256 aliceInBefore = tokens[0].balanceOf(alice);
        uint256 aliceOutBefore = tokens[1].balanceOf(alice);

        medusa.prank(alice);
        try
            router.swapSingleTokenExactIn(address(pool), tokens[0], tokens[1], amountIn, 0, MAX_UINT256, false, bytes(""))
        returns (uint256 amountOut) {
            if (amountOut == 0) revert ZeroAmountOut();

            uint256 aliceInAfter = tokens[0].balanceOf(alice);
            uint256 aliceOutAfter = tokens[1].balanceOf(alice);
            if (aliceInAfter != aliceInBefore - amountIn) {
                revert TokenBalanceDidNotDecrease(address(tokens[0]), aliceInBefore, aliceInAfter, amountIn);
            }
            if (aliceOutAfter != aliceOutBefore + amountOut) {
                revert TokenBalanceDidNotIncrease(address(tokens[1]), aliceOutBefore, aliceOutAfter, amountOut);
            }

            (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
            if (balancesAfter[0] != balancesBefore[0] + amountIn) {
                revert PoolBalanceDidNotChangeByExpectedAmount(0, balancesBefore[0], balancesAfter[0], amountIn);
            }
            if (balancesAfter[1] != balancesBefore[1] - amountOut) {
                revert PoolBalanceDidNotChangeByExpectedAmount(1, balancesBefore[1], balancesAfter[1], amountOut);
            }

            _assertSpotPriceWithinBounds(balancesAfter);
            _assertBptRateNeverDecreases();
        } catch (bytes memory err) {
            _assertExpectedSwapRevert(err);
        }
    }

    /**
     * @notice Fuzz: Exact input swap token1 -> token0
     */
    function swapExactIn1to0(uint256 amountIn) external {
        (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));

        uint256 minSwap = _minSwap(tokens[1]);
        uint256 maxSwap = balancesBefore[1].mulDown(MAX_SWAP_RATIO_EXACT_IN);
        if (maxSwap < minSwap) return;
        amountIn = _boundLocal(amountIn, minSwap, maxSwap);

        uint256 aliceInBefore = tokens[1].balanceOf(alice);
        uint256 aliceOutBefore = tokens[0].balanceOf(alice);

        medusa.prank(alice);
        try
            router.swapSingleTokenExactIn(address(pool), tokens[1], tokens[0], amountIn, 0, MAX_UINT256, false, bytes(""))
        returns (uint256 amountOut) {
            if (amountOut == 0) revert ZeroAmountOut();

            uint256 aliceInAfter = tokens[1].balanceOf(alice);
            uint256 aliceOutAfter = tokens[0].balanceOf(alice);
            if (aliceInAfter != aliceInBefore - amountIn) {
                revert TokenBalanceDidNotDecrease(address(tokens[1]), aliceInBefore, aliceInAfter, amountIn);
            }
            if (aliceOutAfter != aliceOutBefore + amountOut) {
                revert TokenBalanceDidNotIncrease(address(tokens[0]), aliceOutBefore, aliceOutAfter, amountOut);
            }

            (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
            if (balancesAfter[1] != balancesBefore[1] + amountIn) {
                revert PoolBalanceDidNotChangeByExpectedAmount(1, balancesBefore[1], balancesAfter[1], amountIn);
            }
            if (balancesAfter[0] != balancesBefore[0] - amountOut) {
                revert PoolBalanceDidNotChangeByExpectedAmount(0, balancesBefore[0], balancesAfter[0], amountOut);
            }

            _assertSpotPriceWithinBounds(balancesAfter);
            _assertBptRateNeverDecreases();
        } catch (bytes memory err) {
            _assertExpectedSwapRevert(err);
        }
    }

    /**
     * @notice Fuzz: Exact output swap token0 -> token1
     */
    function swapExactOut0to1(uint256 amountOut) external {
        (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));

        uint256 minOut = _minSwap(tokens[1]);
        uint256 maxOut = balancesBefore[1].mulDown(MAX_SWAP_RATIO_EXACT_OUT);
        if (maxOut < minOut) return;
        amountOut = _boundLocal(amountOut, minOut, maxOut);

        uint256 aliceInBefore = tokens[0].balanceOf(alice);
        uint256 aliceOutBefore = tokens[1].balanceOf(alice);

        medusa.prank(alice);
        try
            router.swapSingleTokenExactOut(
                address(pool),
                tokens[0],
                tokens[1],
                amountOut,
                MAX_UINT256,
                MAX_UINT256,
                false,
                bytes("")
            )
        returns (uint256 amountIn) {
            if (amountIn == 0) revert ZeroAmountIn();

            uint256 aliceInAfter = tokens[0].balanceOf(alice);
            uint256 aliceOutAfter = tokens[1].balanceOf(alice);
            if (aliceOutAfter != aliceOutBefore + amountOut) {
                revert TokenBalanceDidNotIncrease(address(tokens[1]), aliceOutBefore, aliceOutAfter, amountOut);
            }
            if (aliceInAfter != aliceInBefore - amountIn) {
                revert TokenBalanceDidNotDecrease(address(tokens[0]), aliceInBefore, aliceInAfter, amountIn);
            }

            (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
            if (balancesAfter[1] != balancesBefore[1] - amountOut) {
                revert PoolBalanceDidNotChangeByExpectedAmount(1, balancesBefore[1], balancesAfter[1], amountOut);
            }
            if (balancesAfter[0] != balancesBefore[0] + amountIn) {
                revert PoolBalanceDidNotChangeByExpectedAmount(0, balancesBefore[0], balancesAfter[0], amountIn);
            }

            _assertSpotPriceWithinBounds(balancesAfter);
            _assertBptRateNeverDecreases();
        } catch (bytes memory err) {
            _assertExpectedSwapRevert(err);
        }
    }

    /**
     * @notice Fuzz: Exact output swap token1 -> token0
     */
    function swapExactOut1to0(uint256 amountOut) external {
        (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));

        uint256 minOut = _minSwap(tokens[0]);
        uint256 maxOut = balancesBefore[0].mulDown(MAX_SWAP_RATIO_EXACT_OUT);
        if (maxOut < minOut) return;
        amountOut = _boundLocal(amountOut, minOut, maxOut);

        uint256 aliceInBefore = tokens[1].balanceOf(alice);
        uint256 aliceOutBefore = tokens[0].balanceOf(alice);

        medusa.prank(alice);
        try
            router.swapSingleTokenExactOut(
                address(pool),
                tokens[1],
                tokens[0],
                amountOut,
                MAX_UINT256,
                MAX_UINT256,
                false,
                bytes("")
            )
        returns (uint256 amountIn) {
            if (amountIn == 0) revert ZeroAmountIn();

            uint256 aliceInAfter = tokens[1].balanceOf(alice);
            uint256 aliceOutAfter = tokens[0].balanceOf(alice);
            if (aliceOutAfter != aliceOutBefore + amountOut) {
                revert TokenBalanceDidNotIncrease(address(tokens[0]), aliceOutBefore, aliceOutAfter, amountOut);
            }
            if (aliceInAfter != aliceInBefore - amountIn) {
                revert TokenBalanceDidNotDecrease(address(tokens[1]), aliceInBefore, aliceInAfter, amountIn);
            }

            (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
            if (balancesAfter[0] != balancesBefore[0] - amountOut) {
                revert PoolBalanceDidNotChangeByExpectedAmount(0, balancesBefore[0], balancesAfter[0], amountOut);
            }
            if (balancesAfter[1] != balancesBefore[1] + amountIn) {
                revert PoolBalanceDidNotChangeByExpectedAmount(1, balancesBefore[1], balancesAfter[1], amountIn);
            }

            _assertSpotPriceWithinBounds(balancesAfter);
            _assertBptRateNeverDecreases();
        } catch (bytes memory err) {
            _assertExpectedSwapRevert(err);
        }
    }

    /**
     * @notice Fuzz (strict): Round-trip swap should not profit trader (tiny rounding dust only)
     * @dev direction=0 means token0->token1->token0, direction=1 means token1->token0->token1
     */
    function roundTripSwapStrict(uint256 amountIn, uint256 direction) external {
        direction = direction & 1;

        uint256 iIn = direction == 0 ? 0 : 1;
        uint256 iMid = direction == 0 ? 1 : 0;

        // Tight scope: only keep the two tokens and the input-side pool balance needed for bounds.
        IERC20 tokenIn;
        IERC20 tokenMid;
        uint256 balInBefore;
        {
            (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));
            tokenIn = tokens[iIn];
            tokenMid = tokens[iMid];
            balInBefore = balancesBefore[iIn];
        }

        uint256 minSwap = _minSwap(tokenIn);
        uint256 maxSwap = balInBefore.mulDown(MAX_SWAP_RATIO_ROUND_TRIP);
        if (maxSwap < minSwap) return;
        amountIn = _boundLocal(amountIn, minSwap, maxSwap);

        uint256 startIn = tokenIn.balanceOf(alice);

        uint256 intermediateAmount;
        {
            medusa.prank(alice);
            (bool ok, uint256 out1) = _trySwapExactInWithUserDeltaAssertions(tokenIn, tokenMid, amountIn);
            if (!ok) return;
            intermediateAmount = out1;
        }

        // If the pool returned zero (should be blocked by ZeroAmountOut), stop.
        if (intermediateAmount == 0) return;

        uint256 finalAmount;
        {
            medusa.prank(alice);
            (bool ok2, uint256 out2) = _trySwapExactInWithUserDeltaAssertions(tokenMid, tokenIn, intermediateAmount);
            if (!ok2) return;
            finalAmount = out2;
        }

        // Strict no-profit: end balance in input token must not exceed start balance (+1 unit dust).
        uint256 endIn = tokenIn.balanceOf(alice);
        uint256 maxAllowed = startIn + 1;
        if (endIn > maxAllowed) revert RoundTripProfitStrict(endIn, maxAllowed, amountIn);

        // Extra integration assertions on the end state.
        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        _assertSpotPriceWithinBounds(balancesAfter);
        _assertBptRateNeverDecreases();
    }

    /**
     * @notice Fuzz: Multiple sequential swaps
     */
    function multipleSwaps(uint256 seed, uint256 count) external {
        count = _boundLocal(count, 1, 5);
        (IERC20[] memory tokens, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        for (uint256 i = 0; i < count; i++) {
            uint256 direction = (seed >> i) & 1;
            uint256 amountSeed = (seed >> (i * 8)) & 0xFF;

            uint256 tokenIndex = direction == 0 ? 0 : 1;
            uint256 minSwap = _minSwap(tokens[tokenIndex]);
            uint256 maxSwap = balances[tokenIndex].mulDown(MAX_SWAP_RATIO_EXACT_IN / 2);
            if (maxSwap < minSwap) continue;
            uint256 amountIn = _boundLocal(amountSeed * 1e15, minSwap, maxSwap);

            medusa.prank(alice);
            if (direction == 0) {
                uint256 aliceInBefore = tokens[0].balanceOf(alice);
                uint256 aliceOutBefore = tokens[1].balanceOf(alice);
                try
                    router.swapSingleTokenExactIn(
                        address(pool),
                        tokens[0],
                        tokens[1],
                        amountIn,
                        0,
                        MAX_UINT256,
                        false,
                        bytes("")
                    )
                returns (uint256 amountOut) {
                    if (amountOut == 0) revert ZeroAmountOut();

                    uint256 aliceInAfter = tokens[0].balanceOf(alice);
                    uint256 aliceOutAfter = tokens[1].balanceOf(alice);
                    if (aliceInAfter != aliceInBefore - amountIn) {
                        revert TokenBalanceDidNotDecrease(address(tokens[0]), aliceInBefore, aliceInAfter, amountIn);
                    }
                    if (aliceOutAfter != aliceOutBefore + amountOut) {
                        revert TokenBalanceDidNotIncrease(address(tokens[1]), aliceOutBefore, aliceOutAfter, amountOut);
                    }

                    (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
                    if (balancesAfter[0] != balances[0] + amountIn) {
                        revert PoolBalanceDidNotChangeByExpectedAmount(0, balances[0], balancesAfter[0], amountIn);
                    }
                    if (balancesAfter[1] != balances[1] - amountOut) {
                        revert PoolBalanceDidNotChangeByExpectedAmount(1, balances[1], balancesAfter[1], amountOut);
                    }

                    balances = balancesAfter;
                    _assertSpotPriceWithinBounds(balancesAfter);
                    _assertBptRateNeverDecreases();
                } catch (bytes memory err) {
                    _assertExpectedSwapRevert(err);
                }
            } else {
                uint256 aliceInBefore = tokens[1].balanceOf(alice);
                uint256 aliceOutBefore = tokens[0].balanceOf(alice);
                try
                    router.swapSingleTokenExactIn(
                        address(pool),
                        tokens[1],
                        tokens[0],
                        amountIn,
                        0,
                        MAX_UINT256,
                        false,
                        bytes("")
                    )
                returns (uint256 amountOut) {
                    if (amountOut == 0) revert ZeroAmountOut();

                    uint256 aliceInAfter = tokens[1].balanceOf(alice);
                    uint256 aliceOutAfter = tokens[0].balanceOf(alice);
                    if (aliceInAfter != aliceInBefore - amountIn) {
                        revert TokenBalanceDidNotDecrease(address(tokens[1]), aliceInBefore, aliceInAfter, amountIn);
                    }
                    if (aliceOutAfter != aliceOutBefore + amountOut) {
                        revert TokenBalanceDidNotIncrease(address(tokens[0]), aliceOutBefore, aliceOutAfter, amountOut);
                    }

                    (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
                    if (balancesAfter[1] != balances[1] + amountIn) {
                        revert PoolBalanceDidNotChangeByExpectedAmount(1, balances[1], balancesAfter[1], amountIn);
                    }
                    if (balancesAfter[0] != balances[0] - amountOut) {
                        revert PoolBalanceDidNotChangeByExpectedAmount(0, balances[0], balancesAfter[0], amountOut);
                    }

                    balances = balancesAfter;
                    _assertSpotPriceWithinBounds(balancesAfter);
                    _assertBptRateNeverDecreases();
                } catch (bytes memory err) {
                    _assertExpectedSwapRevert(err);
                }
            }
        }

        // After all swaps, spot price should remain within bounds (if pool is still in-bounds).
        _assertSpotPriceWithinBounds(balances);
    }

    /***************************************************************************
                              HELPER FUNCTIONS
     ***************************************************************************/

    function _boundLocal(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }

    function _trySwapExactInWithUserDeltaAssertions(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn)
        internal
        returns (bool ok, uint256 amountOut)
    {
        uint256 userInBefore = tokenIn.balanceOf(alice);
        uint256 userOutBefore = tokenOut.balanceOf(alice);

        try router.swapSingleTokenExactIn(address(pool), tokenIn, tokenOut, amountIn, 0, MAX_UINT256, false, bytes(""))
        returns (uint256 out) {
            if (out == 0) revert ZeroAmountOut();
            uint256 userInAfter = tokenIn.balanceOf(alice);
            uint256 userOutAfter = tokenOut.balanceOf(alice);
            if (userInAfter != userInBefore - amountIn) {
                revert TokenBalanceDidNotDecrease(address(tokenIn), userInBefore, userInAfter, amountIn);
            }
            if (userOutAfter != userOutBefore + out) {
                revert TokenBalanceDidNotIncrease(address(tokenOut), userOutBefore, userOutAfter, out);
            }
            return (true, out);
        } catch (bytes memory err) {
            if (err.length == 0) revert RevertedWithoutData();
            _assertExpectedSwapRevert(err);
            return (false, 0);
        }
    }

    function _minSwap(IERC20 token) internal view returns (uint256) {
        // Token identities are known fixtures in BaseMedusaTest (DAI/USDC).
        if (address(token) == address(usdc)) return MIN_SWAP_USDC;
        return MIN_SWAP_DAI;
    }

    function _assertExpectedSwapRevert(bytes memory err) internal pure {
        if (err.length < 4) revert RevertedWithoutData();
        bytes4 sel;
        assembly {
            sel := mload(add(err, 0x20))
        }
        if (sel != GyroECLPMath.AssetBoundsExceeded.selector) revert UnexpectedRevertSelector(sel);
    }

    function _params() internal pure returns (IGyroECLPPool.EclpParams memory p) {
        p.alpha = PARAMS_ALPHA;
        p.beta = PARAMS_BETA;
        p.c = PARAMS_C;
        p.s = PARAMS_S;
        p.lambda = PARAMS_LAMBDA;
    }

    function _derived() internal pure returns (IGyroECLPPool.DerivedEclpParams memory d) {
        d.tauAlpha = IGyroECLPPool.Vector2(TAU_ALPHA_X, TAU_ALPHA_Y);
        d.tauBeta = IGyroECLPPool.Vector2(TAU_BETA_X, TAU_BETA_Y);
        d.u = DERIVED_U;
        d.v = DERIVED_V;
        d.w = DERIVED_W;
        d.z = DERIVED_Z;
        d.dSq = DERIVED_DSQ;
    }

    function _computeSpotPrice(uint256[] memory balances) internal pure returns (uint256 spotPrice) {
        IGyroECLPPool.EclpParams memory p = _params();
        IGyroECLPPool.DerivedEclpParams memory d = _derived();
        (int256 a, int256 b) = GyroECLPMath.computeOffsetFromBalances(balances, p, d);
        return GyroECLPMath.computePrice(balances, p, a, b);
    }

    function _assertSpotPriceWithinBounds(uint256[] memory balances) internal pure {
        uint256 spotPrice = _computeSpotPrice(balances);
        if (spotPrice < uint256(PARAMS_ALPHA) || spotPrice > uint256(PARAMS_BETA)) {
            revert SpotPriceOutOfBounds(spotPrice, uint256(PARAMS_ALPHA), uint256(PARAMS_BETA));
        }
    }

    function _getCurrentBptRate() internal view returns (uint256) {
        uint256 totalSupply = IERC20(address(pool)).totalSupply();
        if (totalSupply == 0) return 0;

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        return _computeBptRate(totalSupply, balances);
    }

    function _computeBptRate(uint256 totalSupply, uint256[] memory balances) internal pure returns (uint256) {
        if (totalSupply == 0) return 0;

        uint256 totalValue = 0;
        for (uint256 i = 0; i < balances.length; i++) {
            totalValue += balances[i];
        }
        return totalValue.divDown(totalSupply);
    }

    function _assertBptRateNeverDecreases() internal {
        uint256 currentRate = _getCurrentBptRate();
        uint256 minAllowed = lastKnownBptRate.mulDown(99999e13);
        if (currentRate < minAllowed) revert BptRateDecreased(currentRate, lastKnownBptRate, minAllowed);
        if (currentRate > lastKnownBptRate) lastKnownBptRate = currentRate;
    }
}
