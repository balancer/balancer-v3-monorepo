// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IAuthorizer } from "../vault/IAuthorizer.sol";

interface IBasicAuthorizer is IAuthorizer {
    // solhint-disable-next-line func-name-mixedcase
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function renounceRole(bytes32 role, address account) external;
}
