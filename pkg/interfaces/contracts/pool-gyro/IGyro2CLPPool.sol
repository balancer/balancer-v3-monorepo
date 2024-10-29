// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { IBasePool } from "../vault/IBasePool.sol";

interface IGyro2CLPPool is IBasePool {
    /**
     * @notice Gyro 2CLP pool configuration.
     * @param name Pool name
     * @param symbol Pool symbol
     * @param sqrtAlpha Square root of alpha (the lowest price in the price interval of the 2CLP price curve)
     * @param sqrtBeta Square root of beta (the highest price in the price interval of the 2CLP price curve)
     */
    struct GyroParams {
        string name;
        string symbol;
        uint256 sqrtAlpha;
        uint256 sqrtBeta;
    }

    /// @notice The informed alpha is greater than beta.
    error SqrtParamsWrong();
}
