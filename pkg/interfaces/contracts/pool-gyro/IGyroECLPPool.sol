// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePool } from "../vault/IBasePool.sol";

interface IGyroECLPPool is IBasePool {
    event ECLPParamsValidated(bool paramsValidated);
    event ECLPDerivedParamsValidated(bool derivedParamsValidated);

    /**
     * @notice Gyro 2CLP pool configuration.
     * @param name Pool name
     * @param symbol Pool symbol
     * @param sqrtAlpha Square root of alpha (the lowest price in the price interval of the 2CLP price curve)
     * @param sqrtBeta Square root of beta (the highest price in the price interval of the 2CLP price curve)
     */
    struct GyroECLPPoolParams {
        string name;
        string symbol;
        Params eclpParams;
        DerivedParams derivedEclpParams;
    }

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
}
