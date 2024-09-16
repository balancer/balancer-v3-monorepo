// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

contract BaseContractsDeployer is Test {
    bool reusingArtifacts;

    constructor() {
        reusingArtifacts = vm.envOr("REUSING_HARDHAT_ARTIFACTS", false);
    }
}
