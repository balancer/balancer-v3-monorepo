// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/concentrated-lps>.

pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import "./SignedFixedPoint.sol";
import "./GyroPoolMath.sol";

// solhint-disable private-vars-leading-underscore

/**
 * @notice ECLP math library. Pretty much a direct translation of the python version.
 * @dev We use *signed* values here because some of the intermediate results can be negative (e.g. coordinates of
 * points in the untransformed circle, "prices" in the untransformed circle).
 */
library GyroECLPMath {
    error RotationVectorWrong();
    error PriceBoundsWrong();
    error RotationVectorNotNormalized();
    error AssetBoundsExceeded();
    error DerivedTauNotNormalized();
    error DerivedZetaWrong();
    error StretchingFactorWrong();
    error DerivedUvwzWrong();
    error InvariantDenominatorWrong();
    error MaxAssetsExceeded();
    error MaxInvariantExceeded();
    error DerivedDsqWrong();

    uint256 internal constant ONEHALF = 0.5e18;
    int256 internal constant ONE = 1e18; // 18 decimal places
    int256 internal constant ONE_XP = 1e38; // 38 decimal places

    using SignedFixedPoint for int256;
    using FixedPoint for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;

    // Anti-overflow limits: Params and DerivedParams (static, only needs to be checked on pool creation).
    int256 internal constant _ROTATION_VECTOR_NORM_ACCURACY = 1e3; // 1e-15 in normal precision
    int256 internal constant _MAX_STRETCH_FACTOR = 1e26; // 1e8   in normal precision
    int256 internal constant _DERIVED_TAU_NORM_ACCURACY_XP = 1e23; // 1e-15 in extra precision
    int256 internal constant _MAX_INV_INVARIANT_DENOMINATOR_XP = 1e43; // 1e5   in extra precision
    int256 internal constant _DERIVED_DSQ_NORM_ACCURACY_XP = 1e23; // 1e-15 in extra precision

    // Anti-overflow limits: Dynamic values (checked before operations that use them).
    int256 internal constant _MAX_BALANCES = 1e34; // 1e16 in normal precision
    int256 internal constant _MAX_INVARIANT = 3e37; // 3e19 in normal precision

    // Note that all t values (not tp or tpp) could consist of uint's, as could all Params. But it's complicated to
    // convert all the time, so we make them all signed. We also store all intermediate values signed. An exception are
    // the functions that are used by the contract because there the values are stored unsigned.
    struct Params {
        // Price bounds (lower and upper). 0 < alpha < beta.
        int256 alpha;
        int256 beta;
        // Rotation vector:
        // phi in (-90 degrees, 0] is the implicit rotation vector. It's stored as a point:
        int256 c; // c = cos(-phi) >= 0. rounded to 18 decimals
        int256 s; //  s = sin(-phi) >= 0. rounded to 18 decimals
        // Invariant: c^2 + s^2 == 1, i.e., the point (c, s) is normalized.
        // Due to rounding, this may not be 1. The term dSq in DerivedParams corrects for this in extra precision

        // Stretching factor:
        int256 lambda; // lambda >= 1 where lambda == 1 is the circle.
    }

    // terms in this struct are stored in extra precision (38 decimals) with final decimal rounded down
    struct DerivedParams {
        Vector2 tauAlpha;
        Vector2 tauBeta;
        int256 u; // from (A chi)_y = lambda * u + v
        int256 v; // from (A chi)_y = lambda * u + v
        int256 w; // from (A chi)_x = w / lambda + z
        int256 z; // from (A chi)_x = w / lambda + z
        int256 dSq; // error in c^2 + s^2 = dSq, used to correct errors in c, s, tau, u,v,w,z calculations
    }

    struct Vector2 {
        int256 x;
        int256 y;
    }

    struct QParams {
        int256 a;
        int256 b;
        int256 c;
    }

    /// @dev Enforces limits and approximate normalization of the rotation vector.
    function validateParams(Params memory params) internal pure {
        if (0 > params.s || params.s > ONE) {
            revert RotationVectorWrong();
        }

        if (0 > params.c || params.c > ONE) {
            revert RotationVectorWrong();
        }

        Vector2 memory sc = Vector2(params.s, params.c);
        int256 scnorm2 = scalarProd(sc, sc); // squared norm

        if (ONE - _ROTATION_VECTOR_NORM_ACCURACY > scnorm2 || scnorm2 > ONE + _ROTATION_VECTOR_NORM_ACCURACY) {
            revert RotationVectorNotNormalized();
        }

        if (params.lambda < 0 || params.lambda > _MAX_STRETCH_FACTOR) {
            revert StretchingFactorWrong();
        }
    }

    /**
     * @notice Enforces limits and approximate normalization of the derived values.
     * @dev Does NOT check for internal consistency of 'derived' with 'params'.
     */
    function validateDerivedParamsLimits(Params memory params, DerivedParams memory derived) external pure {
        int256 norm2;
        norm2 = scalarProdXp(derived.tauAlpha, derived.tauAlpha);

        if (ONE_XP - _DERIVED_TAU_NORM_ACCURACY_XP > norm2 || norm2 > ONE_XP + _DERIVED_TAU_NORM_ACCURACY_XP) {
            revert DerivedTauNotNormalized();
        }

        norm2 = scalarProdXp(derived.tauBeta, derived.tauBeta);

        if (ONE_XP - _DERIVED_TAU_NORM_ACCURACY_XP > norm2 || norm2 > ONE_XP + _DERIVED_TAU_NORM_ACCURACY_XP) {
            revert DerivedTauNotNormalized();
        }

        if (derived.u > ONE_XP) revert DerivedUvwzWrong();
        if (derived.v > ONE_XP) revert DerivedUvwzWrong();
        if (derived.w > ONE_XP) revert DerivedUvwzWrong();
        if (derived.z > ONE_XP) revert DerivedUvwzWrong();

        if (
            ONE_XP - _DERIVED_DSQ_NORM_ACCURACY_XP > derived.dSq || derived.dSq > ONE_XP + _DERIVED_DSQ_NORM_ACCURACY_XP
        ) {
            revert DerivedDsqWrong();
        }

        // NB No anti-overflow checks are required given the checks done above and in validateParams().
        int256 mulDenominator = ONE_XP.divXpU(calcAChiAChiInXp(params, derived) - ONE_XP);

        if (mulDenominator > _MAX_INV_INVARIANT_DENOMINATOR_XP) {
            revert InvariantDenominatorWrong();
        }
    }

    function scalarProd(Vector2 memory t1, Vector2 memory t2) internal pure returns (int256 ret) {
        ret = t1.x.mulDownMag(t2.x) + t1.y.mulDownMag(t2.y);
    }

    /// @dev Scalar product for extra-precision values
    function scalarProdXp(Vector2 memory t1, Vector2 memory t2) internal pure returns (int256 ret) {
        ret = t1.x.mulXp(t2.x) + t1.y.mulXp(t2.y);
    }

    // "Methods" for Params. We could put these into a separate library and import them via 'using' to get method call
    // syntax.

    /**
     * @notice Calculate A t where A is given in Section 2.2.
     * @dev This is reversing rotation and scaling of the ellipse (mapping back to circle) .
     */
    function mulA(Params memory params, Vector2 memory tp) internal pure returns (Vector2 memory t) {
        // NB: This function is only used inside calculatePrice(). This is why we can make two simplifications:
        // 1. We don't correct for precision of s, c using d.dSq because that level of precision is not important in
        // this context;
        // 2. We don't need to check for over/underflow because these are impossible in that context and given the
        // (checked) assumptions on the various values.
        t.x =
            params.c.mulDownMagU(tp.x).divDownMagU(params.lambda) -
            params.s.mulDownMagU(tp.y).divDownMagU(params.lambda);
        t.y = params.s.mulDownMagU(tp.x) + params.c.mulDownMagU(tp.y);
    }

    /**
     * @notice Calculate virtual offset a given invariant r, see calculation in Section 2.1.2.
     * @dev In contrast to virtual reserve offsets in CPMM, these are *subtracted* from the real reserves, moving the
     * curve to the upper-right. They can be positive or negative, but not both can be negative. Calculates
     * `a = r*(A^{-1}tau(beta))_x` rounding up in signed direction. That error in r is scaled by lambda, and so
     * rounding direction is important.
     */
    function virtualOffset0(
        Params memory p,
        DerivedParams memory d,
        Vector2 memory r // overestimate in x component, underestimate in y
    ) internal pure returns (int256 a) {
        // a = r lambda c tau(beta)_x + rs tau(beta)_y
        //       account for 1 factors of dSq (2 s,c factors)
        int256 termXp = d.tauBeta.x.divXpU(d.dSq);
        a = d.tauBeta.x > 0
            ? r.x.mulUpMagU(p.lambda).mulUpMagU(p.c).mulUpXpToNpU(termXp)
            : r.y.mulDownMagU(p.lambda).mulDownMagU(p.c).mulUpXpToNpU(termXp);

        // Use fact that tau(beta)_y > 0, so the required rounding direction is clear.
        a = a + r.x.mulUpMagU(p.s).mulUpXpToNpU(d.tauBeta.y.divXpU(d.dSq));
    }

    /**
     * @notice calculate virtual offset b given invariant r.
     * @dev Calculates b = r*(A^{-1}tau(alpha))_y rounding up in signed direction
     */
    function virtualOffset1(
        Params memory p,
        DerivedParams memory d,
        Vector2 memory r // overestimate in x component, underestimate in y
    ) internal pure returns (int256 b) {
        // b = -r \lambda s tau(alpha)_x + rc tau(alpha)_y
        //       account for 1 factors of dSq (2 s,c factors)
        int256 termXp = d.tauAlpha.x.divXpU(d.dSq);
        b = (d.tauAlpha.x < 0)
            ? r.x.mulUpMagU(p.lambda).mulUpMagU(p.s).mulUpXpToNpU(-termXp)
            : (-r.y).mulDownMagU(p.lambda).mulDownMagU(p.s).mulUpXpToNpU(termXp);

        // Use fact that tau(alpha)_y > 0, so the required rounding direction is clear.
        b = b + r.x.mulUpMagU(p.c).mulUpXpToNpU(d.tauAlpha.y.divXpU(d.dSq));
    }

    /**
     * @notice Maximal value for the real reserves x when the respective other balance is 0 for given invariant.
     * @dev See calculation in Section 2.1.2. Calculation is ordered here for precision, but error in r is magnified
     * by lambda. Rounds down in signed direction
     */
    function maxBalances0(
        Params memory p,
        DerivedParams memory d,
        Vector2 memory r // overestimate in x-component, underestimate in y-component
    ) internal pure returns (int256 xp) {
        // x^+ = r lambda c (tau(beta)_x - tau(alpha)_x) + rs (tau(beta)_y - tau(alpha)_y)
        //      account for 1 factors of dSq (2 s,c factors)

        // Note tauBeta.x > tauAlpha.x, so this is > 0 and rounding direction is clear.
        int256 termXp1 = (d.tauBeta.x - d.tauAlpha.x).divXpU(d.dSq);
        // Note this may be negative, but since tauBeta.y, tauAlpha.y >= 0, it is always in [-1, 1].
        int256 termXp2 = (d.tauBeta.y - d.tauAlpha.y).divXpU(d.dSq);
        xp = r.y.mulDownMagU(p.lambda).mulDownMagU(p.c).mulDownXpToNpU(termXp1);
        xp = xp + (termXp2 > 0 ? r.y.mulDownMagU(p.s) : r.x.mulUpMagU(p.s)).mulDownXpToNpU(termXp2);
    }

    /**
     * @notice Maximal value for the real reserves y when the respective other balance is 0 for given invariant.
     * @dev See calculation in Section 2.1.2. Calculation is ordered here for precision, but erorr in r is magnified
     * by lambda. Rounds down in signed direction
     */
    function maxBalances1(
        Params memory p,
        DerivedParams memory d,
        Vector2 memory r // overestimate in x-component, underestimate in y-component
    ) internal pure returns (int256 yp) {
        // y^+ = r lambda s (tau(beta)_x - tau(alpha)_x) + rc (tau(alpha)_y - tau(beta)_y)
        //      account for 1 factors of dSq (2 s,c factors)
        int256 termXp1 = (d.tauBeta.x - d.tauAlpha.x).divXpU(d.dSq); // note tauBeta.x > tauAlpha.x
        int256 termXp2 = (d.tauAlpha.y - d.tauBeta.y).divXpU(d.dSq);
        yp = r.y.mulDownMagU(p.lambda).mulDownMagU(p.s).mulDownXpToNpU(termXp1);
        yp = yp + (termXp2 > 0 ? r.y.mulDownMagU(p.c) : r.x.mulUpMagU(p.c)).mulDownXpToNpU(termXp2);
    }

    /**
     * @notice Compute the invariant 'r' corresponding to the given values.
     * @dev The invariant can't be negative, but we use a signed value to store it because all the other calculations
     * are happening with signed ints, too. Computes r according to Prop 13 in 2.2.1 Initialization from Real Reserves.
     * Orders operations to achieve best precision. Returns an underestimate and a bound on error size. Enforces
     * anti-overflow limits on balances and the computed invariant in the process.
     */
    function calculateInvariantWithError(
        uint256[] memory balances,
        Params memory params,
        DerivedParams memory derived
    ) public pure returns (int256, int256) {
        (int256 x, int256 y) = (balances[0].toInt256(), balances[1].toInt256());

        if (x + y > _MAX_BALANCES) {
            revert MaxAssetsExceeded();
        }

        int256 atAChi = calcAtAChi(x, y, params, derived);
        (int256 sqrt, int256 err) = calcInvariantSqrt(x, y, params, derived);
        // Calculate the error in the square root term, separates cases based on sqrt >= 1/2
        // somedayTODO: can this be improved for cases of large balances (when xp error magnifies to np)
        // Note: the minimum non-zero value of sqrt is 1e-9 since the minimum argument is 1e-18
        if (sqrt > 0) {
            // err + 1 to account for O(eps_np) term ignored before
            err = (err + 1).divUpMagU(2 * sqrt);
        } else {
            // In the false case here, the extra precision error does not magnify, and so the error inside the sqrt is
            // O(1e-18)
            // somedayTODO: The true case will almost surely never happen (can it be removed)
            err = err > 0 ? GyroPoolMath.sqrt(err.toUint256(), 5).toInt256() : int256(1e9);
        }
        // Calculate the error in the numerator, scale the error by 20 to be sure all possible terms accounted for
        err = ((params.lambda.mulUpMagU(x + y) / ONE_XP) + err + 1) * 20;

        // A chi \cdot A chi > 1, so round it up to round denominator up.
        // Denominator uses extra precision, so we do * 1/denominator so we are sure the calculation doesn't overflow.
        int256 mulDenominator = ONE_XP.divXpU(calcAChiAChiInXp(params, derived) - ONE_XP);
        // NOTE: Anti-overflow limits on mulDenominator are checked on contract creation.

        // As alternative, could do, but could overflow: invariant = (AtAChi.add(sqrt) - err).divXp(denominator);
        int256 invariant = (atAChi + sqrt - err).mulDownXpToNpU(mulDenominator);
        // Error scales if denominator is small.
        // NB: This error calculation computes the error in the expression "numerator / denominator", but in this code
        // We actually use the formula "numerator * (1 / denominator)" to compute the invariant. This affects this line
        // and the one below.
        err = err.mulUpXpToNpU(mulDenominator);
        // Account for relative error due to error in the denominator.
        // Error in denominator is O(epsilon) if lambda<1e11, scale up by 10 to be sure we catch it, and add O(eps).
        // Error in denominator is lambda^2 * 2e-37 and scales relative to the result / denominator.
        // Scale by a constant to account for errors in the scaling factor itself and limited compounding.
        // Calculating lambda^2 without decimals so that the calculation will never overflow, the lost precision isn't
        // important.
        err =
            err +
            ((invariant.mulUpXpToNpU(mulDenominator) * ((params.lambda * params.lambda) / 1e36)) * 40) /
            ONE_XP +
            1;

        if (invariant + err > _MAX_INVARIANT) {
            revert MaxInvariantExceeded();
        }

        return (invariant, err);
    }

    /// @dev Calculate At \cdot A chi, ignores rounding direction. We will later compensate for the rounding error.
    function calcAtAChi(
        int256 x,
        int256 y,
        Params memory p,
        DerivedParams memory d
    ) internal pure returns (int256 val) {
        // to save gas, pre-compute dSq^2 as it will be used 3 times
        int256 dSq2 = d.dSq.mulXpU(d.dSq);

        // (cx - sy) * (w/lambda + z) / lambda
        //      account for 2 factors of dSq (4 s,c factors)
        int256 termXp = (d.w.divDownMagU(p.lambda) + d.z).divDownMagU(p.lambda).divXpU(dSq2);
        val = (x.mulDownMagU(p.c) - y.mulDownMagU(p.s)).mulDownXpToNpU(termXp);

        // (x lambda s + y lambda c) * u, note u > 0
        int256 termNp = x.mulDownMagU(p.lambda).mulDownMagU(p.s) + y.mulDownMagU(p.lambda).mulDownMagU(p.c);
        val = val + termNp.mulDownXpToNpU(d.u.divXpU(dSq2));

        // (sx+cy) * v, note v > 0
        termNp = x.mulDownMagU(p.s) + y.mulDownMagU(p.c);
        val = val + termNp.mulDownXpToNpU(d.v.divXpU(dSq2));
    }

    /**
     * @notice Calculates A chi \cdot A chi in extra precision.
     * @dev This can be >1 (and involves factor of lambda^2). We can compute it in extra precision without overflowing
     * because it will be at most 38 + 16 digits (38 from decimals, 2*8 from lambda^2 if lambda=1e8). Since we will
     * only divide by this later, we will not need to worry about overflow in that operation if done in the right way.
     */
    function calcAChiAChiInXp(Params memory p, DerivedParams memory d) internal pure returns (int256 val) {
        // To save gas, pre-compute dSq^3 as it will be used 4 times.
        int256 dSq3 = d.dSq.mulXpU(d.dSq).mulXpU(d.dSq);

        // (A chi)_y^2 = lambda^2 u^2 + lambda 2 u v + v^2
        //      account for 3 factors of dSq (6 s,c factors)
        // SOMEDAY: In these calcs, a calculated value is multiplied by lambda and lambda^2, resp, which implies some
        // error amplification. It's fine because we're doing it in extra precision here, but would still be nice if it
        // could be avoided, perhaps by splitting up the numbers into a high and low part.
        val = p.lambda.mulUpMagU((2 * d.u).mulXpU(d.v).divXpU(dSq3));
        // For lambda^2 u^2 factor in rounding error in u since lambda could be big.
        // Note: lambda^2 is multiplied at the end to be sure the calculation doesn't overflow, but this can lose some
        // precision
        val = val + ((d.u + 1).mulXpU(d.u + 1).divXpU(dSq3)).mulUpMagU(p.lambda).mulUpMagU(p.lambda);
        // The next line converts from extre precision to normal precision post-computation while rounding up.
        val = val + (d.v).mulXpU(d.v).divXpU(dSq3);

        // (A chi)_x^2 = (w/lambda + z)^2
        //      account for 3 factors of dSq (6 s,c factors)
        int256 termXp = d.w.divUpMagU(p.lambda) + d.z;
        val = val + termXp.mulXpU(termXp).divXpU(dSq3);
    }

    /// @dev Calculate -(At)_x ^2 (A chi)_y ^2 + (At)_x ^2, rounding down in signed direction
    function calcMinAtxAChiySqPlusAtxSq(
        int256 x,
        int256 y,
        Params memory p,
        DerivedParams memory d
    ) internal pure returns (int256 val) {
        ////////////////////////////////////////////////////////////////////////////////////
        // (At)_x^2 (A chi)_y^2 = (x^2 c^2 - xy2sc + y^2 s^2) (u^2 + 2uv/lambda + v^2/lambda^2)
        //      account for 4 factors of dSq (8 s,c factors)
        //
        // (At)_x^2 = (x^2 c^2 - xy2sc + y^2 s^2)/lambda^2
        //      account for 1 factor of dSq (2 s,c factors)
        ////////////////////////////////////////////////////////////////////////////////////
        int256 termNp = x.mulUpMagU(x).mulUpMagU(p.c).mulUpMagU(p.c) + y.mulUpMagU(y).mulUpMagU(p.s).mulUpMagU(p.s);
        termNp = termNp - x.mulDownMagU(y).mulDownMagU(p.c * 2).mulDownMagU(p.s);

        int256 termXp = d.u.mulXpU(d.u) +
            (2 * d.u).mulXpU(d.v).divDownMagU(p.lambda) +
            d.v.mulXpU(d.v).divDownMagU(p.lambda).divDownMagU(p.lambda);
        termXp = termXp.divXpU(d.dSq.mulXpU(d.dSq).mulXpU(d.dSq).mulXpU(d.dSq));
        val = (-termNp).mulDownXpToNpU(termXp);

        // Now calculate (At)_x^2 accounting for possible rounding error to round down.
        // Need to do 1/dSq in a way so that there is no overflow for large balances.
        val =
            val +
            (termNp - 9).divDownMagU(p.lambda).divDownMagU(p.lambda).mulDownXpToNpU(
                SignedFixedPoint.ONE_XP.divXpU(d.dSq)
            );
    }

    /**
     * @notice Calculate 2(At)_x * (At)_y * (A chi)_x * (A chi)_y, ignores rounding direction.
     * @dev This ignores rounding direction and is corrected for later.
     */
    function calc2AtxAtyAChixAChiy(
        int256 x,
        int256 y,
        Params memory p,
        DerivedParams memory d
    ) internal pure returns (int256 val) {
        ////////////////////////////////////////////////////////////////////////////////////
        // = ((x^2 - y^2)sc + yx(c^2-s^2)) * 2 * (zu + (wu + zv)/lambda + wv/lambda^2)
        //      account for 4 factors of dSq (8 s,c factors)
        ////////////////////////////////////////////////////////////////////////////////////
        int256 termNp = (x.mulDownMagU(x) - y.mulUpMagU(y)).mulDownMagU(2 * p.c).mulDownMagU(p.s);
        int256 xy = y.mulDownMagU(2 * x);
        termNp = termNp + xy.mulDownMagU(p.c).mulDownMagU(p.c) - xy.mulDownMagU(p.s).mulDownMagU(p.s);

        int256 termXp = d.z.mulXpU(d.u) + d.w.mulXpU(d.v).divDownMagU(p.lambda).divDownMagU(p.lambda);
        termXp = termXp + (d.w.mulXpU(d.u) + d.z.mulXpU(d.v)).divDownMagU(p.lambda);
        termXp = termXp.divXpU(d.dSq.mulXpU(d.dSq).mulXpU(d.dSq).mulXpU(d.dSq));

        val = termNp.mulDownXpToNpU(termXp);
    }

    /// @dev Calculate -(At)_y ^2 (A chi)_x ^2 + (At)_y ^2, rounding down in signed direction.
    function calcMinAtyAChixSqPlusAtySq(
        int256 x,
        int256 y,
        Params memory p,
        DerivedParams memory d
    ) internal pure returns (int256 val) {
        ////////////////////////////////////////////////////////////////////////////////////
        // (At)_y^2 (A chi)_x^2 = (x^2 s^2 + xy2sc + y^2 c^2) * (z^2 + 2zw/lambda + w^2/lambda^2)
        //      account for 4 factors of dSq (8 s,c factors)
        // (At)_y^2 = (x^2 s^2 + xy2sc + y^2 c^2)
        //      account for 1 factor of dSq (2 s,c factors)
        ////////////////////////////////////////////////////////////////////////////////////
        int256 termNp = x.mulUpMagU(x).mulUpMagU(p.s).mulUpMagU(p.s) + y.mulUpMagU(y).mulUpMagU(p.c).mulUpMagU(p.c);
        termNp = termNp + x.mulUpMagU(y).mulUpMagU(p.s * 2).mulUpMagU(p.c);

        int256 termXp = d.z.mulXpU(d.z) + d.w.mulXpU(d.w).divDownMagU(p.lambda).divDownMagU(p.lambda);
        termXp = termXp + (2 * d.z).mulXpU(d.w).divDownMagU(p.lambda);
        termXp = termXp.divXpU(d.dSq.mulXpU(d.dSq).mulXpU(d.dSq).mulXpU(d.dSq));
        val = (-termNp).mulDownXpToNpU(termXp);

        // Now calculate (At)_y^2 accounting for possible rounding error to round down.
        // Need to do 1/dSq in a way so that there is no overflow for large balances.
        val = val + (termNp - 9).mulDownXpToNpU(SignedFixedPoint.ONE_XP.divXpU(d.dSq));
    }

    /**
     * @notice Calculates the square root of the invariant.
     * @dev Rounds down. Also returns an estimate for the error of the term under the sqrt (!) and without the regular
     * normal-precision error of O(1e-18).
     */
    function calcInvariantSqrt(
        int256 x,
        int256 y,
        Params memory p,
        DerivedParams memory d
    ) internal pure returns (int256 val, int256 err) {
        val = calcMinAtxAChiySqPlusAtxSq(x, y, p, d) + calc2AtxAtyAChixAChiy(x, y, p, d);
        val = val + calcMinAtyAChixSqPlusAtySq(x, y, p, d);
        // Error inside the square root is O((x^2 + y^2) * eps_xp) + O(eps_np), where eps_xp=1e-38, eps_np=1e-18.
        // Note that in terms of rounding down, error corrects for calc2AtxAtyAChixAChiy().
        // However, we also use this error to correct the invariant for an overestimate in swaps, it is all the same
        // order though.
        // Note the O(eps_np) term will be dealt with later, so not included yet.
        // Note that the extra precision term doesn't propagate unless balances are > 100b.
        err = (x.mulUpMagU(x) + y.mulUpMagU(y)) / 1e38;
        // We will account for the error later after the square root.
        // Mathematically, terms in square root > 0, so treat as 0 if it is < 0 because of rounding error.
        val = val > 0 ? GyroPoolMath.sqrt(val.toUint256(), 5).toInt256() : int256(0);
    }

    /**
     * @notice Spot price of token 0 in units of token 1.
     * @dev See Prop. 12 in 2.1.6 Computing Prices
     */
    function calcSpotPrice0in1(
        uint256[] memory balances,
        Params memory params,
        DerivedParams memory derived,
        int256 invariant
    ) external pure returns (uint256 px) {
        // Shift by virtual offsets to get v(t).
        // Ignore r rounding for spot price, precision will be lost in TWAP anyway.
        Vector2 memory r = Vector2(invariant, invariant);
        Vector2 memory ab = Vector2(virtualOffset0(params, derived, r), virtualOffset1(params, derived, r));
        Vector2 memory vec = Vector2(balances[0].toInt256() - ab.x, balances[1].toInt256() - ab.y);

        // Transform to circle to get Av(t).
        vec = mulA(params, vec);
        // Compute prices on circle.
        Vector2 memory pc = Vector2(vec.x.divDownMagU(vec.y), ONE);

        // Convert prices back to ellipse
        // NB: These operations check for overflow because the price pc[0] might be large when vex.y is small.
        // SOMEDAY I think this probably can't actually happen due to our bounds on the different values. In this case
        // we could do this unchecked as well.
        int256 pgx = scalarProd(pc, mulA(params, Vector2(ONE, 0)));
        px = pgx.divDownMag(scalarProd(pc, mulA(params, Vector2(0, ONE)))).toUint256();
    }

    /**
     * @notice Check that post-swap balances obey maximal asset bounds.
     * @dev newBalance = post-swap balance of one asset. assetIndex gives the index of the provided asset
     * (0 = X, 1 = Y)
     */
    function checkAssetBounds(
        Params memory params,
        DerivedParams memory derived,
        Vector2 memory invariant,
        int256 newBal,
        uint8 assetIndex
    ) internal pure {
        if (assetIndex == 0) {
            int256 xPlus = maxBalances0(params, derived, invariant);
            if (!(newBal <= _MAX_BALANCES && newBal <= xPlus)) revert AssetBoundsExceeded();
            return;
        }
        {
            int256 yPlus = maxBalances1(params, derived, invariant);
            if (!(newBal <= _MAX_BALANCES && newBal <= yPlus)) revert AssetBoundsExceeded();
        }
    }

    function calcOutGivenIn(
        uint256[] memory balances,
        uint256 amountIn,
        bool tokenInIsToken0,
        Params memory params,
        DerivedParams memory derived,
        Vector2 memory invariant
    ) external pure returns (uint256 amountOut) {
        function(int256, Params memory, DerivedParams memory, Vector2 memory) pure returns (int256) calcGiven;
        uint8 ixIn;
        uint8 ixOut;
        if (tokenInIsToken0) {
            ixIn = 0;
            ixOut = 1;
            calcGiven = calcYGivenX;
        } else {
            ixIn = 1;
            ixOut = 0;
            calcGiven = calcXGivenY;
        }

        int256 balInNew = (balances[ixIn] + amountIn).toInt256(); // checked because amountIn is given by the user.
        checkAssetBounds(params, derived, invariant, balInNew, ixIn);
        int256 balOutNew = calcGiven(balInNew, params, derived, invariant);
        // Make sub checked as an extra check against numerical error; but this really should never happen
        amountOut = balances[ixOut] - balOutNew.toUint256();
        // The above line guarantees that amountOut <= balances[ixOut].
    }

    function calcInGivenOut(
        uint256[] memory balances,
        uint256 amountOut,
        bool tokenInIsToken0,
        Params memory params,
        DerivedParams memory derived,
        Vector2 memory invariant
    ) external pure returns (uint256 amountIn) {
        function(int256, Params memory, DerivedParams memory, Vector2 memory) pure returns (int256) calcGiven;
        uint8 ixIn;
        uint8 ixOut;
        if (tokenInIsToken0) {
            ixIn = 0;
            ixOut = 1;
            calcGiven = calcXGivenY; // this reverses compared to calcOutGivenIn
        } else {
            ixIn = 1;
            ixOut = 0;
            calcGiven = calcYGivenX; // this reverses compared to calcOutGivenIn
        }

        if (!(amountOut <= balances[ixOut])) revert AssetBoundsExceeded();
        int256 balOutNew = (balances[ixOut] - amountOut).toInt256();
        int256 balInNew = calcGiven(balOutNew, params, derived, invariant);
        // The checks in the following two lines should really always succeed; we keep them as extra safety against
        // numerical error.
        checkAssetBounds(params, derived, invariant, balInNew, ixIn);
        amountIn = balInNew.toUint256() - balances[ixIn];
    }

    /**
     * @dev Variables are named for calculating y given x. To calculate x given y, change x->y, s->c, c->s, a_>b, b->a,
     * tauBeta.x -> -tauAlpha.x, tauBeta.y -> tauAlpha.y. Also, calculates an overestimate of calculated reserve
     * post-swap.
     */
    function solveQuadraticSwap(
        int256 lambda,
        int256 x,
        int256 s,
        int256 c,
        Vector2 memory r, // overestimate in x component, underestimate in y
        Vector2 memory ab,
        Vector2 memory tauBeta,
        int256 dSq
    ) internal pure returns (int256) {
        // x component will round up, y will round down, use extra precision.
        Vector2 memory lamBar;
        lamBar.x = SignedFixedPoint.ONE_XP - SignedFixedPoint.ONE_XP.divDownMagU(lambda).divDownMagU(lambda);
        // Note: The following cannot become negative even with errors because we require lambda >= 1 and divUpMag
        // returns the exact result if the quotient is representable in 18 decimals.
        lamBar.y = SignedFixedPoint.ONE_XP - SignedFixedPoint.ONE_XP.divUpMagU(lambda).divUpMagU(lambda);
        // Using qparams struct to avoid "stack too deep".
        QParams memory q;
        // Shift by the virtual offsets.
        // Note that we want an overestimate of offset here so that -x'*lambar*s*c is overestimated in signed
        // direction. Account for 1 factor of dSq (2 s,c factors).
        int256 xp = x - ab.x;
        if (xp > 0) {
            q.b = (-xp).mulDownMagU(s).mulDownMagU(c).mulUpXpToNpU(lamBar.y.divXpU(dSq));
        } else {
            q.b = (-xp).mulUpMagU(s).mulUpMagU(c).mulUpXpToNpU(lamBar.x.divXpU(dSq) + 1);
        }

        // x component will round up, y will round down, use extra precision.
        // Account for 1 factor of dSq (2 s,c factors).
        Vector2 memory sTerm;
        // We wil take sTerm = 1 - sTerm below, using multiple lines to avoid "stack too deep".
        sTerm.x = lamBar.y.mulDownMagU(s).mulDownMagU(s).divXpU(dSq);
        sTerm.y = lamBar.x.mulUpMagU(s);
        sTerm.y = sTerm.y.mulUpMagU(s).divXpU(dSq + 1) + 1; // account for rounding error in dSq, divXp
        sTerm = Vector2(SignedFixedPoint.ONE_XP - sTerm.x, SignedFixedPoint.ONE_XP - sTerm.y);
        // ^^ NB: The components of sTerm are non-negative: We only need to worry about sTerm.y. This is non-negative
        // because, because of bounds on lambda lamBar <= 1 - 1e-16, and division by dSq ensures we have enough
        // precision so that rounding errors are never magnitude 1e-16.

        // Now compute the argument of the square root.
        q.c = -calcXpXpDivLambdaLambda(x, r, lambda, s, c, tauBeta, dSq);
        q.c = q.c + r.y.mulDownMagU(r.y).mulDownXpToNpU(sTerm.y);
        // The square root is always being subtracted, so round it down to overestimate the end balance.
        // Mathematically, terms in square root > 0, so treat as 0 if it is < 0 because of rounding error.
        q.c = q.c > 0 ? GyroPoolMath.sqrt(q.c.toUint256(), 5).toInt256() : int256(0);

        // Calculate the result in q.a.
        if (q.b - q.c > 0) {
            q.a = (q.b - q.c).mulUpXpToNpU(SignedFixedPoint.ONE_XP.divXpU(sTerm.y) + 1);
        } else {
            q.a = (q.b - q.c).mulUpXpToNpU(SignedFixedPoint.ONE_XP.divXpU(sTerm.x));
        }

        // Lastly, add the offset, note that we want an overestimate of offset here.
        return q.a + ab.y;
    }

    /**
     * @notice Calculates x'x'/λ^2 where x' = x - b = x - r (A^{-1}tau(beta))_x
     * @dev Calculates an overestimate. To calculate y'y', change x->y, s->c, c->s, tauBeta.x -> -tauAlpha.x,
     * tauBeta.y -> tauAlpha.y
     */
    function calcXpXpDivLambdaLambda(
        int256 x,
        Vector2 memory r, // overestimate in x component, underestimate in y
        int256 lambda,
        int256 s,
        int256 c,
        Vector2 memory tauBeta,
        int256 dSq
    ) internal pure returns (int256) {
        //////////////////////////////////////////////////////////////////////////////////
        // x'x'/lambda^2 = r^2 c^2 tau(beta)_x^2
        //      + ( r^2 2s c tau(beta)_x tau(beta)_y - rx 2c tau(beta)_x ) / lambda
        //      + ( r^2 s^2 tau(beta)_y^2 - rx 2s tau(beta)_y + x^2 ) / lambda^2
        //////////////////////////////////////////////////////////////////////////////////
        // to save gas, pre-compute dSq^2 as it will be used 3 times, and r.x^2 as it will be used 2-3 times
        // sqVars = (dSq^2, r.x^2)
        Vector2 memory sqVars = Vector2(dSq.mulXpU(dSq), r.x.mulUpMagU(r.x));

        QParams memory q; // for working terms
        // q.a = r^2 s 2c tau(beta)_x tau(beta)_y
        //      account for 2 factors of dSq (4 s,c factors)
        int256 termXp = tauBeta.x.mulXpU(tauBeta.y).divXpU(sqVars.x);
        if (termXp > 0) {
            q.a = sqVars.y.mulUpMagU(2 * s);
            q.a = q.a.mulUpMagU(c).mulUpXpToNpU(termXp + 7); // +7 account for rounding in termXp
        } else {
            q.a = r.y.mulDownMagU(r.y).mulDownMagU(2 * s);
            q.a = q.a.mulDownMagU(c).mulUpXpToNpU(termXp);
        }

        // -rx 2c tau(beta)_x
        //      account for 1 factor of dSq (2 s,c factors)
        if (tauBeta.x < 0) {
            // +3 account for rounding in extra precision terms
            q.b = r.x.mulUpMagU(x).mulUpMagU(2 * c).mulUpXpToNpU(-tauBeta.x.divXpU(dSq) + 3);
        } else {
            q.b = (-r.y).mulDownMagU(x).mulDownMagU(2 * c).mulUpXpToNpU(tauBeta.x.divXpU(dSq));
        }
        // q.a later needs to be divided by lambda.
        q.a = q.a + q.b;

        // q.b = r^2 s^2 tau(beta)_y^2
        //      account for 2 factors of dSq (4 s,c factors)
        termXp = tauBeta.y.mulXpU(tauBeta.y).divXpU(sqVars.x) + 7; // +7 account for rounding in termXp
        q.b = sqVars.y.mulUpMagU(s);
        q.b = q.b.mulUpMagU(s).mulUpXpToNpU(termXp);

        // q.c = -rx 2s tau(beta)_y, recall that tauBeta.y > 0 so round lower in magnitude
        //      account for 1 factor of dSq (2 s,c factors)
        q.c = (-r.y).mulDownMagU(x).mulDownMagU(2 * s).mulUpXpToNpU(tauBeta.y.divXpU(dSq));

        // (q.b + q.c + x^2) / lambda
        q.b = q.b + q.c + x.mulUpMagU(x);
        q.b = q.b > 0 ? q.b.divUpMagU(lambda) : q.b.divDownMagU(lambda);

        // Remaining calculation is (q.a + q.b) / lambda
        q.a = q.a + q.b;
        q.a = q.a > 0 ? q.a.divUpMagU(lambda) : q.a.divDownMagU(lambda);

        // + r^2 c^2 tau(beta)_x^2
        //      account for 2 factors of dSq (4 s,c factors)
        termXp = tauBeta.x.mulXpU(tauBeta.x).divXpU(sqVars.x) + 7; // +7 account for rounding in termXp
        int256 val = sqVars.y.mulUpMagU(c).mulUpMagU(c);
        return (val.mulUpXpToNpU(termXp)) + q.a;
    }

    /**
     * @notice compute y such that (x, y) satisfy the invariant at the given parameters.
     * @dev We calculate an overestimate of y. See Prop 14 in section 2.2.2 Trade Execution
     */
    function calcYGivenX(
        int256 x,
        Params memory params,
        DerivedParams memory d,
        Vector2 memory r // overestimate in x component, underestimate in y
    ) internal pure returns (int256 y) {
        // Want to overestimate the virtual offsets except in a particular setting that will be corrected for later.
        // Note that the error correction in the invariant should more than make up for uncaught rounding directions
        // (in 38 decimals) in virtual offsets.
        Vector2 memory ab = Vector2(virtualOffset0(params, d, r), virtualOffset1(params, d, r));
        y = solveQuadraticSwap(params.lambda, x, params.s, params.c, r, ab, d.tauBeta, d.dSq);
    }

    function calcXGivenY(
        int256 y,
        Params memory params,
        DerivedParams memory d,
        Vector2 memory r // overestimate in x component, underestimate in y
    ) internal pure returns (int256 x) {
        // Want to overestimate the virtual offsets except in a particular setting that will be corrected for later.
        // Note that the error correction in the invariant should more than make up for uncaught rounding directions
        // (in 38 decimals) in virtual offsets.
        Vector2 memory ba = Vector2(virtualOffset1(params, d, r), virtualOffset0(params, d, r));
        // Change x->y, s->c, c->s, b->a, a->b, tauBeta.x -> -tauAlpha.x, tauBeta.y -> tauAlpha.y vs calcYGivenX.
        x = solveQuadraticSwap(
            params.lambda,
            y,
            params.c,
            params.s,
            r,
            ba,
            Vector2(-d.tauAlpha.x, d.tauAlpha.y),
            d.dSq
        );
    }
}
