// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/concentrated-lps>.

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { Gyro2CLPPool } from "../Gyro2CLPPool.sol";

contract Gyro2CLPPoolMock is Gyro2CLPPool {
    uint256 private _overrideSqrtAlpha;
    uint256 private _overrideSqrtBeta;

    constructor(GyroParams memory params, IVault vault) Gyro2CLPPool(params, vault) {
        _overrideSqrtAlpha = params.sqrtAlpha;
        _overrideSqrtBeta = params.sqrtBeta;
    }

    function setSqrtParams(uint256 newSqrtAlpha, uint256 newSqrtBeta) external {
        _overrideSqrtAlpha = newSqrtAlpha;
        _overrideSqrtBeta = newSqrtBeta;
    }

    /// @notice Return the parameters that configure a 2CLP (sqrtAlpha and sqrtBeta).
    function _getSqrtAlphaAndBeta() internal view override returns (uint256 sqrtAlpha, uint256 sqrtBeta) {
        return (_overrideSqrtAlpha, _overrideSqrtBeta);
    }
}
