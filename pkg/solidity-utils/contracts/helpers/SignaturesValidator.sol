// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.0;

import "@balancer-labs/v3-interfaces/contracts/solidity-utils/openzeppelin/IERC1271.sol";

import "./EOASignaturesValidator.sol";
import "../openzeppelin/Address.sol";

/**
 * @dev Utility for signing Solidity function calls.
 */
abstract contract SignaturesValidator is EOASignaturesValidator {
    using Address for address;

    function _isValidSignature(
        address account,
        bytes32 digest,
        bytes memory signature
    ) internal view virtual override returns (bool) {
        if (account.isContract()) {
            return IERC1271(account).isValidSignature(digest, signature) == IERC1271.isValidSignature.selector;
        } else {
            return super._isValidSignature(account, digest, signature);
        }
    }
}
