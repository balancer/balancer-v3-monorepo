// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.7.0 <0.9.0;

import "./IAuthorizerAdaptor.sol";

/**
 * @notice Interface for `AuthorizerAdaptorEntrypoint`.
 */
interface IAuthorizerAdaptorEntrypoint is IAuthorizerAdaptor {
    /**
     * @notice Returns the Authorizer Adaptor
     */
    function getAuthorizerAdaptor() external view returns (IAuthorizerAdaptor);
}
