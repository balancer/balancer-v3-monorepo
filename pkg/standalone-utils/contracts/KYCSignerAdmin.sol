// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IKYCSignerAdmin } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IKYCSignerAdmin.sol";

/**
 * @notice Singleton registry for the KYC signer address used by pool factories that deploy KYC-enabled pools.
 * @dev Deployed once per chain. Factories that support KYC hooks read the current signer at pool creation time and
 * pass it as an immutable to the hook constructor. If the KYC vendor rotates keys, update the signer here; existing
 * pools keep their original signer for the duration of the sale.
 */
contract KYCSignerAdmin is Ownable2Step, IKYCSignerAdmin {
    /// @notice The address currently authorized to sign KYC approvals for new pools.
    address private _kycSigner;

    constructor(address owner, address kycSigner) Ownable(owner) {
        _setKYCSigner(kycSigner);
    }

    /// @inheritdoc IKYCSignerAdmin
    function getKYCSigner() external view returns (address) {
        return _kycSigner;
    }

    /// @inheritdoc IKYCSignerAdmin
    function setKYCSigner(address kycSigner) external onlyOwner {
        _setKYCSigner(kycSigner);
    }

    function _setKYCSigner(address kycSigner) private {
        require(kycSigner != address(0), KYCSignerCannotBeZero());

        emit KYCSignerSet(_kycSigner, kycSigner);

        _kycSigner = kycSigner;
    }
}
