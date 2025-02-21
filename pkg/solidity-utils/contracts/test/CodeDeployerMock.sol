// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;
import { CodeDeployer } from "../helpers/CodeDeployer.sol";

contract CodeDeployerMock {
    event CodeDeployed(address destination);

    function deploy(bytes memory data, bool preventExecution) external {
        address destination = CodeDeployer.deploy(data, preventExecution);
        emit CodeDeployed(destination);
    }
}
