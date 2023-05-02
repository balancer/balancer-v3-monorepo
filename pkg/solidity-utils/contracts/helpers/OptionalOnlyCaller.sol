// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IOptionalOnlyCaller.sol";
import "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";

import "./SignaturesValidator.sol";

abstract contract OptionalOnlyCaller is IOptionalOnlyCaller, SignaturesValidator {
    mapping(address => bool) private _isOnlyCallerEnabled;

    bytes32 private constant _SET_ONLY_CALLER_CHECK_TYPEHASH =
        keccak256("SetOnlyCallerCheck(address user,bool enabled,uint256 nonce)");

    /**
     * @dev Reverts if the verification mechanism is enabled and the given address is not the caller.
     * @param user - Address to validate as the only allowed caller, if the verification is enabled.
     */
    modifier optionalOnlyCaller(address user) {
        _verifyCaller(user);
        _;
    }

    function setOnlyCallerCheck(bool enabled) external override {
        _setOnlyCallerCheck(msg.sender, enabled);
    }

    function setOnlyCallerCheckWithSignature(address user, bool enabled, bytes memory signature) external override {
        bytes32 structHash = keccak256(abi.encode(_SET_ONLY_CALLER_CHECK_TYPEHASH, user, enabled, getNextNonce(user)));
        _ensureValidSignature(user, structHash, signature, Errors.INVALID_SIGNATURE);
        _setOnlyCallerCheck(user, enabled);
    }

    function _setOnlyCallerCheck(address user, bool enabled) private {
        _isOnlyCallerEnabled[user] = enabled;
        emit OnlyCallerOptIn(user, enabled);
    }

    function isOnlyCallerEnabled(address user) external view override returns (bool) {
        return _isOnlyCallerEnabled[user];
    }

    function _verifyCaller(address user) private view {
        if (_isOnlyCallerEnabled[user]) {
            _require(msg.sender == user, Errors.SENDER_NOT_ALLOWED);
        }
    }
}
