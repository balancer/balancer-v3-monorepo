// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";

/**
 * @notice Building block for performing access control on external functions.
 * @dev This contract is used via the `authenticate` modifier (or the `_authenticateCaller` function), which can be
 * applied to external functions to make them only callable by authorized accounts.
 *
 * Derived contracts must implement the `_canPerform` function, which holds the actual access control logic.
 */
abstract contract Authentication is IAuthentication {
    bytes32 private immutable _actionIdDisambiguator;

    /**
     * @dev The main purpose of the `actionIdDisambiguator` is to prevent accidental function selector collisions in
     * multi-contract systems.
     *
     * There are two main uses for it:
     *  - if the contract is a singleton, any unique identifier can be used to make the associated action identifiers
     *    unique. The contract's own address is a good option.
     *  - if the contract belongs to a family that shares action identifiers for the same functions, an identifier
     *    shared by the entire family (and no other contract) should be used instead.
     */
    constructor(bytes32 actionIdDisambiguator) {
        _actionIdDisambiguator = actionIdDisambiguator;
    }

    /// @dev Reverts unless the caller is allowed to call this function. Should only be applied to external functions.
    modifier authenticate() {
        _authenticateCaller();
        _;
    }

    /// @dev Reverts unless the caller is allowed to call the entry point function.
    function _authenticateCaller() internal view {
        bytes32 actionId = getActionId(msg.sig);

        if (!_canPerform(actionId, msg.sender)) {
            revert SenderNotAllowed();
        }
    }

    /// @inheritdoc IAuthentication
    function getActionId(bytes4 selector) public view override returns (bytes32) {
        // Each external function is dynamically assigned an action identifier as the hash of the disambiguator and the
        // function selector. Disambiguation is necessary to avoid potential collisions in the function selectors of
        // multiple contracts.
        return keccak256(abi.encodePacked(_actionIdDisambiguator, selector));
    }

    /**
     * @dev Derived contracts must implement this function to perform the actual access control logic.
     * @param actionId The action identifier associated with an external function
     * @param user The account performing the action
     * @return success True if the action is permitted
     */
    function _canPerform(bytes32 actionId, address user) internal view virtual returns (bool);
}
