// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/concentrated-lps>.

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { Gyro2CLPPool } from "../Gyro2CLPPool.sol";

contract Gyro2CLPPoolMock is Gyro2CLPPool {
    uint256 private _sqrtAlpha;
    uint256 private _sqrtBeta;

    constructor(GyroParams memory params, IVault vault) Gyro2CLPPool(params, vault) {
        _sqrtAlpha = params.sqrtAlpha;
        _sqrtBeta = params.sqrtBeta;
    }

    function _sqrtParameters() internal view override returns (uint256[2] memory sqrtParameters) {
        sqrtParameters[0] = _sqrtAlpha;
        sqrtParameters[1] = _sqrtBeta;
        return sqrtParameters;
    }
}
