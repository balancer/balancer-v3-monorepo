// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePool } from "../vault/IBasePool.sol";

interface IGyroECLPPool is IBasePool {
    event ECLPParamsValidated(bool paramsValidated);
    event ECLPDerivedParamsValidated(bool derivedParamsValidated);

    /**
     * @notice Gyro ECLP pool configuration.
     * @param name Pool name
     * @param symbol Pool symbol
     * @param eclpParams Parameters to configure the E-CLP pool, with 18 decimals
     * @param derivedEclpParams Parameters calculated off-chain based on eclpParams. 38 decimals for higher precision
     */
    struct GyroECLPPoolParams {
        string name;
        string symbol;
        EclpParams eclpParams;
        DerivedEclpParams derivedEclpParams;
    }

    /**
     * @notice Struct containing parameters to build the ellipse which describes the pricing curve of an E-CLP pool.
     * @dev Note that all values are positive and could consist of uint's. However, this would require converting to
     * int numerous times because of int operations, so we store them as int to simplify the code.
     *
     * @param alpha Lower price limit. alpha > 0
     * @param beta Upper price limit. beta > alpha > 0
     * @param c `c = cos(-phi) >= 0`, rounded to 18 decimals. Phi is the rotation angle of the ellipse
     * @param s `s = sin(-phi) >= 0`, rounded to 18 decimals. Phi is the rotation angle of the ellipse
     * @param lambda Stretching factor, lambda >= 1. When lambda == 1, we have a perfect circle
     */
    struct EclpParams {
        int256 alpha;
        int256 beta;
        int256 c;
        int256 s;
        // Invariant: c^2 + s^2 == 1, i.e., the point (c, s) is normalized.
        // Due to rounding, this may not be 1. The term dSq in DerivedParams corrects for this in extra precision
        int256 lambda;
    }

    /**
     * @notice Struct containing parameters calculated based on EclpParams, off-chain.
     * @dev All these parameters can be calculated using the EclpParams, but they're calculated off-chain to save gas
     * and increase the precision. Therefore, the numbers are stored with 38 decimals precision. Please refer to
     * https://docs.gyro.finance/gyroscope-protocol/technical-documents, document "E-CLP high-precision
     * calculations.pdf", for further explanations on how to obtain the parameters below.
     */
    struct DerivedEclpParams {
        Vector2 tauAlpha;
        Vector2 tauBeta;
        int256 u;
        int256 v;
        int256 w;
        int256 z;
        int256 dSq;
    }

    /// @notice Struct containing a 2D vector.
    struct Vector2 {
        int256 x;
        int256 y;
    }
}
