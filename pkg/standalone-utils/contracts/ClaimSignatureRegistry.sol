// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @notice Simple signature registry for claimants to record their agreement to terms and conditions.
 * See https://forum.balancer.fi/t/bip-892-distribution-of-rescued-funds-from-balancer-v2-november-3rd-2025-attacks.
 */
contract ClaimSignatureRegistry {
    using MessageHashUtils for bytes;

    /// @notice Emitted when a signature is recorded for a signer.
    event SignatureRecorded(address indexed signer);

    /// @notice Signer cannot be address(0).
    error InvalidSigner();

    /// @notice There is already a valid signature recorded for the given signer.
    error SignatureAlreadyRecorded(address signer);

    /// @notice Signature is invalid for the given signer.
    error InvalidSignature(address signer);

    // solhint-disable-next-line var-name-mixedcase
    bytes32 public immutable TERMS_DIGEST;

    mapping(address => bytes) public signatures;

    constructor() {
        // solhint-disable max-line-length
        string
            memory terms = "I ACCEPT BALANCER'S T&C APPLICABLE TO THIS CLAIM, INCL. ALL PROVISIONS OF THE ToU AND RELEVANT GOV RESOLUTIONS, INCL. LIMITATION OF LIABILITY, MANDATORY ARBITRATION AND RISK DISCLOSURES. I HEREBY CONFIRM & AGREE TO THE FOLLOWING:\n\n"
            "My acceptance constitutes full final settlement & release of any past, present, & future claims, liabilities, demands, actions, causes of action, damages, or losses of any kind, known or unknown, arising out of or related to the Balancer exploit.\n"
            "This waiver incl. claims and any right to participate in any class or collective action against the Balancer Foundation & all affiliated entities, as well as their respective officers, directors, contributors, service providers, employees, contractors, advisors, agents, successors, & assigns.\n"
            "I acknowledge & agree to the Safe Harbor Agreement in all its terms (as approved by Balancer governance resolution).\n"
            "I understand that my claim will not be processed unless I accept these terms in full & without modification.";

        TERMS_DIGEST = bytes(terms).toEthSignedMessageHash();
    }

    /// @notice Records a signature for the sender agreeing to the terms.
    function recordSignature(bytes memory signature) external {
        _recordSignatureFor(signature, msg.sender);
    }

    /// @notice Records a signature for a specified signer agreeing to the terms.
    function recordSignatureFor(bytes memory signature, address signer) external {
        _recordSignatureFor(signature, signer);
    }

    function _recordSignatureFor(bytes memory signature, address signer) internal {
        require(signer != address(0), InvalidSigner());
        require(signatures[signer].length == 0, SignatureAlreadyRecorded(signer));
        require(SignatureChecker.isValidSignatureNow(signer, TERMS_DIGEST, signature), InvalidSignature(signer));

        emit SignatureRecorded(signer);
        signatures[signer] = signature;
    }
}
