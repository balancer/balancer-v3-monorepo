// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IKYCSignerAdmin {
    /**
     * @notice Emitted when the KYC signer is updated.
     * @param previousSigner The old signer address
     * @param newSigner The new signer address
     */
    event KYCSignerSet(address indexed previousSigner, address indexed newSigner);

    /// @notice The provided KYC signer address is zero.
    error KYCSignerCannotBeZero();

    /**
     * @notice Getter for the current KYC signer address.
     * @return kycSigner Address of the current signer
     */
    function getKYCSigner() external view returns (address kycSigner);

    /**
     * @notice Setter for the KYC signer address.
     * @dev This is a permissioned function that can only be called by the admin contract owner.
     * @param kycSigner Address of the new signer
     */
    function setKYCSigner(address kycSigner) external;
}
