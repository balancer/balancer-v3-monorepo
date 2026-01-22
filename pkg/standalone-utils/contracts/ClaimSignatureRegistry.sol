// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract ClaimSignatureRegistry {
    using MessageHashUtils for bytes;

    error InvalidSignature();

    // solhint-disable-next-line var-name-mixedcase
    bytes32 public immutable TERMS_DIGEST;

    mapping(address => bytes) public signatures;

    constructor() {
        // solhint-disable max-line-length
        string memory terms = "I confirm and agree to the following:\n"
        "- I accept the terms and conditions applicable to this claim, including all provisions of the Balancer Terms of Use and all relevant Balancer governance resolutions.\n"
        "- I acknowledge and agree that my acceptance constitutes a full and final settlement and release of any and all past, present, and future claims, liabilities, demands, actions, causes of action, damages, or losses of any kind-whether known or unknown-arising out of or related to the Balancer V2 exploit.\n"
        "- This waiver expressly includes claims against the Balancer Foundation, Balancer OpCo Limited, Balancer Onchain Limited and all affiliated entities, as well as their respective officers, directors, contributors, service providers, employees, contractors, advisors, agents, successors, and assigns (collectively, the 'Released Parties').\n"
        "- I acknowledge the limitation of liability, mandatory arbitration and all risk disclosures set forth in the Balancer Terms of Use.\n"
        "- I waive and relinquish any right to participate in any class or collective action related to the V2 exploit or the Balancer Protocol.\n"
        "- I acknowledge and agree to the SEAL Safe Harbor Agreement which was approved by governance resolution and can offer legal protection to whitehats who aid in the recovery of assets during an active exploit."
        "- I understand that my claim will not be processed unless I accept these terms in full and without modification.";

        TERMS_DIGEST = bytes(terms).toEthSignedMessageHash();
    }

    function recordSignature(bytes memory signature) external {
        _recordSignatureFor(signature, msg.sender);
    }

    function recordSignatureFor(bytes memory signature, address signer) external {
        _recordSignatureFor(signature, signer);
    }

    function _recordSignatureFor(bytes memory signature, address signer) internal {
        bool isValid = SignatureChecker.isValidSignatureNow(signer, TERMS_DIGEST, signature);

        if (isValid == false) {
            revert InvalidSignature();
        }

        signatures[signer] = signature;
    }
}
