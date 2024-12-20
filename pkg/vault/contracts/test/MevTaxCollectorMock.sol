// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IMevTaxCollector } from "@balancer-labs/v3-interfaces/contracts/vault/IMevTaxCollector.sol";

contract MevTaxCollectorMock is IMevTaxCollector {
    function chargeMevTax(address pool) external payable {
        return;
    }
}
