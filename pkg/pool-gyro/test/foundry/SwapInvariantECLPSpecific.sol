// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { PoolRoleAccounts, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { GyroECLPPoolFactory } from "../../contracts/GyroECLPPoolFactory.sol";
import { GyroECLPMath } from "../../contracts/lib/GyroECLPMath.sol";

/**
 * @notice Fuzz tests asserting that the E-CLP invariant never decreases across a swap.
 * @dev The pool parameters are fixed (see the constants below); liquidity, swap amount, swap direction and token
 * decimals are fuzzed. Pools are created inside the test body with freshly deployed tokens, so the real decimal
 * scaling path in the Vault is exercised.
 *
 * Every pool is initialized at a spot price of exactly 1. The E-CLP is homogeneous of degree 1, so the spot price
 * depends only on the ratio between the two balances; that ratio is the constant `_PRICE_ONE_BALANCE_RATIO` for
 * these parameters. Only the liquidity scale is fuzzed, and the second balance is derived from the first.
 */
contract SwapInvariantECLPSpecificTest is BaseVaultTest {
    using CastingHelpers for address[];

    /// @dev Everything a test needs to know about a freshly created pool, in the Vault's token order.
    struct PoolSetup {
        address pool;
        IERC20 token0;
        IERC20 token1;
        uint8 decimals0;
        uint8 decimals1;
    }

    uint256 internal constant _SWAP_FEE_PERCENTAGE = 1e14; // 0.01%

    uint8 internal constant _MIN_DECIMALS = 6;
    uint8 internal constant _MAX_DECIMALS = 18;

    // Balance bounds for token 0 (scaled 18-decimal values). Token 1 is ~9999x larger (see
    // `_PRICE_ONE_BALANCE_RATIO`), so the upper bound is what keeps the sum of the balances below `_MAX_BALANCES`
    // (1e34). The lower bound keeps the token 0 raw amount at 6 decimals at or above 1e10 units, so that the
    // truncation performed by `_toRawAmount` perturbs the balance ratio by at most ~1e-10 in relative terms.
    uint256 internal constant _MIN_BALANCE0_SCALED18 = 1e22;
    uint256 internal constant _MAX_BALANCE0_SCALED18 = 1e26;

    // Smallest trade size considered; large enough to be nonzero even for a 6-decimal token.
    uint256 internal constant _MIN_SWAP_SCALED18 = 1e16;

    // Amount minted to the LP for every freshly created token.
    uint256 internal constant _TOKEN_MINT_AMOUNT = 1e32;

    /**
     * @dev Ratio `balance1 / balance0` that puts the pool at a spot price of exactly 1, as an 18-decimal number.
     * Derived from the virtual offset form used by `GyroECLPMath.virtualOffset0/1`, where
     * `(A^-1 tau) = (lambda*c*tau.x + s*tau.y, -lambda*s*tau.x + c*tau.y)`, and
     * `x(p)/r = (A^-1 tauBeta)_x - (A^-1 tau(p))_x`, `y(p)/r = (A^-1 tauAlpha)_y - (A^-1 tau(p))_y`.
     * Since `c == s`, `tau(1) = (0, 1)`, which gives `x(1)/r = 0.0200582737739962149...` and
     * `y(1)/r = 200.5626794660776018...`, hence `y/x = 9998.99999999448846341...`.
     */
    uint256 internal constant _PRICE_ONE_BALANCE_RATIO = 9998999999994488463412;

    /**
     * @dev Maximum accepted absolute deviation of the realized spot price from 1, in 18-decimal fixed point.
     * Rounding the balances to the token decimals perturbs the ratio by at most ~6e-11 in relative terms over these
     * bounds (measured), but the price is extremely insensitive to the ratio at this point of the curve
     * (`d(ln p)/d(ln ratio) ~ 6.3e-7`), so that only accounts for ~4e-17 of price deviation. Sweeping thresholds over
     * 10000 fuzz runs each, the worst observed deviation was 45 wei (4.5e-17 relative), for both
     * `GyroECLPMath.computePrice` and the unclamped `GyroECLPMath.calcSpotPrice0in1`; 100 wei then held over 50000
     * runs. This bound leaves a ~20x margin over that measurement.
     */
    uint256 internal constant _MAX_PRICE_DEVIATION = 1000;

    // Price interval is [0.980392156862745098, 1.000000630371029932] with a 45 degree rotation and a stretch factor
    // of 300. Note that the target price of 1 sits very close to `beta`: at price 1 the pool holds only ~0.01% of
    // the reachable range of token 0, and ~99.99% of the reachable range of token 1.
    int256 internal constant _PARAMS_ALPHA = 980392156862745098;
    int256 internal constant _PARAMS_BETA = 1000000630371029932;
    int256 internal constant _PARAMS_C = 707106781186547524;
    int256 internal constant _PARAMS_S = 707106781186547524;
    int256 internal constant _PARAMS_LAMBDA = 300000000000000000000;

    // Derived params calculated offchain based on the params above, using the jupyter notebook file on
    // "pkg/pool-hooks/jupyter/SurgeECLP.ipynb" (reimplemented in exact integer arithmetic, as the notebook runs in
    // float64, which is too imprecise for 38-decimal output with `beta` this close to 1).
    int256 internal constant _TAU_ALPHA_X = -94773130622350963813402481283118800045;
    int256 internal constant _TAU_ALPHA_Y = 31906953976191491086066439875451340751;
    int256 internal constant _TAU_BETA_X = 9455562426453687808195961460162005;
    int256 internal constant _TAU_BETA_Y = 99999999552961694941282054418046780509;
    int256 internal constant _U = 47391293092388708696875030401893946255;
    int256 internal constant _V = 65953476764576592938898894892506970790;
    int256 internal constant _W = 34046522788385101889007253374479656388;
    int256 internal constant _Z = -47381837529962255009077554770064379269;
    int256 internal constant _D_SQ = 99999999999999999886624093342106115200;

    // Ensures a unique CREATE2 salt when more than one pool is created in the same test.
    uint256 internal _poolNonce;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testSwapExactInInvariantNeverDecreases__Fuzz(
        uint256 balance0Scaled18,
        uint256 swapAmountScaled18,
        bool swap0To1,
        uint8 decimalsA,
        uint8 decimalsB
    ) public {
        decimalsA = uint8(bound(decimalsA, _MIN_DECIMALS, _MAX_DECIMALS));
        decimalsB = uint8(bound(decimalsB, _MIN_DECIMALS, _MAX_DECIMALS));
        balance0Scaled18 = bound(balance0Scaled18, _MIN_BALANCE0_SCALED18, _MAX_BALANCE0_SCALED18);

        PoolSetup memory setup = _createAndInitPoolAtPriceOne(decimalsA, decimalsB, balance0Scaled18);

        _assertSpotPriceIsOne(setup.pool);

        (IERC20 tokenIn, IERC20 tokenOut) = swap0To1 ? (setup.token0, setup.token1) : (setup.token1, setup.token0);

        // Cap the trade at 10% of the token 0 balance, in both directions. Token 0 is by far the scarcer side here
        // (the pool starts near `beta`), so it is what limits the reachable trade size whichever way the swap goes.
        swapAmountScaled18 = bound(swapAmountScaled18, _MIN_SWAP_SCALED18, balance0Scaled18 / 10);
        uint256 amountInRaw = _toRawAmount(swapAmountScaled18, swap0To1 ? setup.decimals0 : setup.decimals1);
        vm.assume(amountInRaw > 0);

        uint256 invariantBefore = _computeInvariant(setup.pool);

        vm.prank(lp);
        try
            router.swapSingleTokenExactIn(setup.pool, tokenIn, tokenOut, amountInRaw, 0, MAX_UINT256, false, bytes(""))
        {
            // Swap succeeded; fall through to the invariant check.
        } catch {
            // The trade is not reachable for these balances (e.g. it would drain the outgoing token). Reject the run
            // rather than asserting on a state that never changed.
            vm.assume(false);
        }

        uint256 invariantAfter = _computeInvariant(setup.pool);

        assertGe(invariantAfter, invariantBefore, "Invariant decreased on EXACT_IN swap");
    }

    function testSwapExactOutInvariantNeverDecreases__Fuzz(
        uint256 balance0Scaled18,
        uint256 swapAmountScaled18,
        bool swap0To1,
        uint8 decimalsA,
        uint8 decimalsB
    ) public {
        decimalsA = uint8(bound(decimalsA, _MIN_DECIMALS, _MAX_DECIMALS));
        decimalsB = uint8(bound(decimalsB, _MIN_DECIMALS, _MAX_DECIMALS));
        balance0Scaled18 = bound(balance0Scaled18, _MIN_BALANCE0_SCALED18, _MAX_BALANCE0_SCALED18);

        PoolSetup memory setup = _createAndInitPoolAtPriceOne(decimalsA, decimalsB, balance0Scaled18);

        _assertSpotPriceIsOne(setup.pool);

        (IERC20 tokenIn, IERC20 tokenOut) = swap0To1 ? (setup.token0, setup.token1) : (setup.token1, setup.token0);

        // Cap the trade at 10% of the token 0 balance, for the same reason as in the EXACT_IN test.
        swapAmountScaled18 = bound(swapAmountScaled18, _MIN_SWAP_SCALED18, balance0Scaled18 / 10);
        uint256 amountOutRaw = _toRawAmount(swapAmountScaled18, swap0To1 ? setup.decimals1 : setup.decimals0);
        vm.assume(amountOutRaw > 0);

        uint256 invariantBefore = _computeInvariant(setup.pool);

        vm.prank(lp);
        try
            router.swapSingleTokenExactOut(
                setup.pool,
                tokenIn,
                tokenOut,
                amountOutRaw,
                MAX_UINT256,
                MAX_UINT256,
                false,
                bytes("")
            )
        {
            // Swap succeeded; fall through to the invariant check.
        } catch {
            vm.assume(false);
        }

        uint256 invariantAfter = _computeInvariant(setup.pool);

        assertGe(invariantAfter, invariantBefore, "Invariant decreased on EXACT_OUT swap");
    }

    /// @dev No default pool is needed; every fuzz run builds its own pool with freshly deployed tokens.
    function createPool() internal pure override returns (address, bytes memory) {
        return (address(0), bytes(""));
    }

    /// @inheritdoc BaseVaultTest
    function initPool() internal pure override {
        // solhint-disable-previous-line no-empty-blocks
    }

    function createPoolFactory() internal override returns (address) {
        return address(new GyroECLPPoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1"));
    }

    /**
     * @notice Deploys two tokens, creates an E-CLP pool with them, and seeds it at a spot price of exactly 1.
     * @dev The tokens are returned in the Vault's (sorted) order, together with the decimals that ended up at each
     * index. The caller's `decimalsA` / `decimalsB` are assigned to whichever token sorted first; since both are
     * fuzzed over the same range, the joint distribution of `(decimals0, decimals1)` is unaffected.
     *
     * @param decimalsA Decimals of the first deployed token
     * @param decimalsB Decimals of the second deployed token
     * @param balance0Scaled18 Initial liquidity of the token at index 0, as an 18-decimal value
     * @return setup The created pool, its tokens and their decimals, in the Vault's token order
     */
    function _createAndInitPoolAtPriceOne(
        uint8 decimalsA,
        uint8 decimalsB,
        uint256 balance0Scaled18
    ) internal returns (PoolSetup memory setup) {
        IERC20 tokenA = _createAndFundToken("TKNA", decimalsA);
        IERC20 tokenB = _createAndFundToken("TKNB", decimalsB);

        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = address(tokenA);
        tokenAddresses[1] = address(tokenB);

        setup.pool = _createPoolWithTokens(tokenAddresses);

        (IERC20[] memory sortedTokens, , , ) = vault.getPoolTokenInfo(setup.pool);
        setup.token0 = sortedTokens[0];
        setup.token1 = sortedTokens[1];
        (setup.decimals0, setup.decimals1) = setup.token0 == tokenA ? (decimalsA, decimalsB) : (decimalsB, decimalsA);

        uint256 balance1Scaled18 = (balance0Scaled18 * _PRICE_ONE_BALANCE_RATIO) / FixedPoint.ONE;

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = _toRawAmount(balance0Scaled18, setup.decimals0);
        amountsIn[1] = _toRawAmount(balance1Scaled18, setup.decimals1);

        vm.prank(lp);
        router.initialize(setup.pool, sortedTokens, amountsIn, 0, false, bytes(""));
    }

    function _createPoolWithTokens(address[] memory tokenAddresses) internal returns (address newPool) {
        PoolRoleAccounts memory roleAccounts;
        IRateProvider[] memory rateProviders = new IRateProvider[](2);

        IGyroECLPPool.EclpParams memory params = IGyroECLPPool.EclpParams({
            alpha: _PARAMS_ALPHA,
            beta: _PARAMS_BETA,
            c: _PARAMS_C,
            s: _PARAMS_S,
            lambda: _PARAMS_LAMBDA
        });

        IGyroECLPPool.DerivedEclpParams memory derivedParams = IGyroECLPPool.DerivedEclpParams({
            tauAlpha: IGyroECLPPool.Vector2(_TAU_ALPHA_X, _TAU_ALPHA_Y),
            tauBeta: IGyroECLPPool.Vector2(_TAU_BETA_X, _TAU_BETA_Y),
            u: _U,
            v: _V,
            w: _W,
            z: _Z,
            dSq: _D_SQ
        });

        newPool = GyroECLPPoolFactory(poolFactory).create(
            "Gyro E-CLP Pool",
            "ECLP-POOL",
            vault.buildTokenConfig(tokenAddresses.asIERC20(), rateProviders),
            params,
            derivedParams,
            roleAccounts,
            _SWAP_FEE_PERCENTAGE,
            address(0),
            false,
            false,
            bytes32(_poolNonce++)
        );

        vm.label(newPool, "eclp pool");
    }

    function _createAndFundToken(string memory name, uint8 decimals) internal returns (IERC20 token) {
        ERC20TestToken newToken = createERC20(name, decimals);
        newToken.mint(lp, _TOKEN_MINT_AMOUNT);

        vm.startPrank(lp);
        newToken.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(newToken), address(router), type(uint160).max, type(uint48).max);
        vm.stopPrank();

        token = IERC20(address(newToken));
    }

    /// @dev Asserts that the spot price realized on initialization is 1, within `_MAX_PRICE_DEVIATION`.
    function _assertSpotPriceIsOne(address poolToQuery) internal view {
        uint256 price = _computeSpotPrice(poolToQuery);
        uint256 deviation = price > FixedPoint.ONE ? price - FixedPoint.ONE : FixedPoint.ONE - price;

        assertLe(deviation, _MAX_PRICE_DEVIATION, "Pool was not initialized at a spot price of 1");
    }

    /// @dev Spot price of token 0 in units of token 1, computed through the same path used by `ECLPSurgeHook`.
    function _computeSpotPrice(address poolToQuery) internal view returns (uint256) {
        uint256[] memory balancesLiveScaled18 = vault.getCurrentLiveBalances(poolToQuery);
        (
            IGyroECLPPool.EclpParams memory eclpParams,
            IGyroECLPPool.DerivedEclpParams memory derivedParams
        ) = IGyroECLPPool(poolToQuery).getECLPParams();

        (int256 a, int256 b) = GyroECLPMath.computeOffsetFromBalances(balancesLiveScaled18, eclpParams, derivedParams);

        return GyroECLPMath.computePrice(balancesLiveScaled18, eclpParams, a, b);
    }

    function _computeInvariant(address poolToQuery) internal view returns (uint256) {
        uint256[] memory balancesLiveScaled18 = vault.getCurrentLiveBalances(poolToQuery);
        return IBasePool(poolToQuery).computeInvariant(balancesLiveScaled18, Rounding.ROUND_DOWN);
    }

    function _toRawAmount(uint256 amountScaled18, uint8 decimals) internal pure returns (uint256) {
        return amountScaled18 / (10 ** (18 - decimals));
    }
}
