// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { PoolRoleAccounts, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { GyroECLPPoolFactory } from "../../contracts/GyroECLPPoolFactory.sol";

/**
 * @notice Fuzz tests asserting that the E-CLP invariant never decreases across a swap.
 * @dev The pool parameters are fixed (see the constants below); liquidity, swap amount, swap direction and token
 * decimals are fuzzed. Pools are created inside the test body with freshly deployed tokens, so the real decimal
 * scaling path in the Vault is exercised.
 */
contract SwapInvariantECLPTest is BaseVaultTest {
    using CastingHelpers for address[];

    uint256 internal constant _SWAP_FEE_PERCENTAGE = 1e14; // 0.01%

    uint8 internal constant _MIN_DECIMALS = 6;
    uint8 internal constant _MAX_DECIMALS = 18;

    // Balance bounds (scaled 18-decimal values). The upper bound is well below `_MAX_BALANCES` (1e34); with
    // lambda = 300 the invariant is amplified far above the raw balances, so this keeps runs away from
    // `MaxInvariantExceeded` while still spanning six orders of magnitude of liquidity.
    uint256 internal constant _MIN_BALANCE_SCALED18 = 1e18;
    uint256 internal constant _MAX_BALANCE_SCALED18 = 1e24;

    // Amount minted to the LP for every freshly created token.
    uint256 internal constant _TOKEN_MINT_AMOUNT = 1e32;

    // Price interval is [0.985, 1.00000000001] with a 45 degree rotation and a stretch factor of 300.
    int256 internal constant _PARAMS_ALPHA = 985000000000000000;
    int256 internal constant _PARAMS_BETA = 1000000000010000000;
    int256 internal constant _PARAMS_C = 707106781186547524;
    int256 internal constant _PARAMS_S = 707106781186547524;
    int256 internal constant _PARAMS_LAMBDA = 300000000000000000000;

    // Derived params calculated offchain based on the params above, using the jupyter notebook file on
    // "pkg/pool-hooks/jupyter/SurgeECLP.ipynb" (reimplemented in exact integer arithmetic, as the notebook runs in
    // float64, which is too imprecise for 38-decimal output with `beta` this close to 1).
    int256 internal constant _TAU_ALPHA_X = -91493988419787776594885987781898350465;
    int256 internal constant _TAU_ALPHA_Y = 40359014891839719231299707943792939038;
    int256 internal constant _TAU_BETA_X = 149999999999249999746221820010;
    int256 internal constant _TAU_BETA_Y = 99999999999999999830812046672178057838;
    int256 internal constant _U = 45746994284893888245201924224826740362;
    int256 internal constant _V = 70179507445919859451489224453129709791;
    int256 internal constant _W = 29820492554080140265946915561154463438;
    int256 internal constant _Z = -45746994134893888245951924648668780338;
    int256 internal constant _D_SQ = 99999999999999999886624093342106115200;

    // Ensures a unique CREATE2 salt when more than one pool is created in the same test.
    uint256 internal _poolNonce;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testSwapExactInInvariantNeverDecreases__Fuzz(
        uint256 balanceAScaled18,
        uint256 balanceBScaled18,
        uint256 swapAmountScaled18,
        bool swapAToB,
        uint8 decimalsA,
        uint8 decimalsB
    ) public {
        decimalsA = uint8(bound(decimalsA, _MIN_DECIMALS, _MAX_DECIMALS));
        decimalsB = uint8(bound(decimalsB, _MIN_DECIMALS, _MAX_DECIMALS));
        balanceAScaled18 = bound(balanceAScaled18, _MIN_BALANCE_SCALED18, _MAX_BALANCE_SCALED18);
        balanceBScaled18 = bound(balanceBScaled18, _MIN_BALANCE_SCALED18, _MAX_BALANCE_SCALED18);

        (address newPool, IERC20 tokenA, IERC20 tokenB) = _createAndInitPool(
            decimalsA,
            decimalsB,
            balanceAScaled18,
            balanceBScaled18
        );

        (IERC20 tokenIn, IERC20 tokenOut) = swapAToB ? (tokenA, tokenB) : (tokenB, tokenA);
        uint8 decimalsIn = swapAToB ? decimalsA : decimalsB;
        uint256 balanceInScaled18 = swapAToB ? balanceAScaled18 : balanceBScaled18;

        // Cap the trade at 10% of the incoming side; larger trades on this very narrow, very asymmetric interval
        // almost always exhaust the reachable reserves of the outgoing token.
        swapAmountScaled18 = bound(swapAmountScaled18, _MIN_BALANCE_SCALED18 / 1e6, balanceInScaled18 / 10);
        uint256 amountInRaw = _toRawAmount(swapAmountScaled18, decimalsIn);
        vm.assume(amountInRaw > 0);

        uint256 invariantBefore = _computeInvariant(newPool);

        vm.prank(lp);
        try router.swapSingleTokenExactIn(newPool, tokenIn, tokenOut, amountInRaw, 0, MAX_UINT256, false, bytes("")) {
            // Swap succeeded; fall through to the invariant check.
        } catch {
            // The trade is not reachable for these balances (e.g. it would drain the outgoing token). Reject the run
            // rather than asserting on a state that never changed.
            vm.assume(false);
        }

        uint256 invariantAfter = _computeInvariant(newPool);

        assertGe(invariantAfter, invariantBefore, "Invariant decreased on EXACT_IN swap");
    }

    function testSwapExactOutInvariantNeverDecreases__Fuzz(
        uint256 balanceAScaled18,
        uint256 balanceBScaled18,
        uint256 swapAmountScaled18,
        bool swapAToB,
        uint8 decimalsA,
        uint8 decimalsB
    ) public {
        decimalsA = uint8(bound(decimalsA, _MIN_DECIMALS, _MAX_DECIMALS));
        decimalsB = uint8(bound(decimalsB, _MIN_DECIMALS, _MAX_DECIMALS));
        balanceAScaled18 = bound(balanceAScaled18, _MIN_BALANCE_SCALED18, _MAX_BALANCE_SCALED18);
        balanceBScaled18 = bound(balanceBScaled18, _MIN_BALANCE_SCALED18, _MAX_BALANCE_SCALED18);

        (address newPool, IERC20 tokenA, IERC20 tokenB) = _createAndInitPool(
            decimalsA,
            decimalsB,
            balanceAScaled18,
            balanceBScaled18
        );

        (IERC20 tokenIn, IERC20 tokenOut) = swapAToB ? (tokenA, tokenB) : (tokenB, tokenA);
        uint8 decimalsOut = swapAToB ? decimalsB : decimalsA;
        uint256 balanceOutScaled18 = swapAToB ? balanceBScaled18 : balanceAScaled18;

        // Cap the trade at 10% of the outgoing side, for the same reason as in the EXACT_IN test.
        swapAmountScaled18 = bound(swapAmountScaled18, _MIN_BALANCE_SCALED18 / 1e6, balanceOutScaled18 / 10);
        uint256 amountOutRaw = _toRawAmount(swapAmountScaled18, decimalsOut);
        vm.assume(amountOutRaw > 0);

        uint256 invariantBefore = _computeInvariant(newPool);

        vm.prank(lp);
        try
            router.swapSingleTokenExactOut(
                newPool,
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

        uint256 invariantAfter = _computeInvariant(newPool);

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
     * @notice Deploys two tokens with the given decimals, creates an E-CLP pool with them, and seeds it.
     * @dev The returned token order matches the input order (A, B); the Vault's internal order may differ.
     *
     * @param decimalsA Decimals of the first token
     * @param decimalsB Decimals of the second token
     * @param balanceAScaled18 Initial liquidity of the first token, as an 18-decimal value
     * @param balanceBScaled18 Initial liquidity of the second token, as an 18-decimal value
     * @return newPool Address of the created pool
     * @return tokenA First token
     * @return tokenB Second token
     */
    function _createAndInitPool(
        uint8 decimalsA,
        uint8 decimalsB,
        uint256 balanceAScaled18,
        uint256 balanceBScaled18
    ) internal returns (address newPool, IERC20 tokenA, IERC20 tokenB) {
        tokenA = _createAndFundToken("TKNA", decimalsA);
        tokenB = _createAndFundToken("TKNB", decimalsB);

        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = address(tokenA);
        tokenAddresses[1] = address(tokenB);

        newPool = _createPoolWithTokens(tokenAddresses);

        (IERC20[] memory sortedTokens, , , ) = vault.getPoolTokenInfo(newPool);

        uint256[] memory amountsIn = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            amountsIn[i] = sortedTokens[i] == tokenA
                ? _toRawAmount(balanceAScaled18, decimalsA)
                : _toRawAmount(balanceBScaled18, decimalsB);
        }

        vm.prank(lp);
        router.initialize(newPool, sortedTokens, amountsIn, 0, false, bytes(""));
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

    function _computeInvariant(address poolToQuery) internal view returns (uint256) {
        uint256[] memory balancesLiveScaled18 = vault.getCurrentLiveBalances(poolToQuery);
        return IBasePool(poolToQuery).computeInvariant(balancesLiveScaled18, Rounding.ROUND_DOWN);
    }

    function _toRawAmount(uint256 amountScaled18, uint8 decimals) internal pure returns (uint256) {
        return amountScaled18 / (10 ** (18 - decimals));
    }
}
