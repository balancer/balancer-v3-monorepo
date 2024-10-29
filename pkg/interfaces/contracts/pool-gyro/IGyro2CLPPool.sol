// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { IBasePool } from "../vault/IBasePool.sol";

interface IGyro2CLPPool is IBasePool {
    /**
     * @notice
     * @dev
     */
    struct GyroParams {
        string name;
        string symbol;
        uint256 sqrtAlpha;
        uint256 sqrtBeta;
    }

    error SqrtParamsWrong();
    error SupportsOnlyTwoTokens();
    error NotImplemented();
}
