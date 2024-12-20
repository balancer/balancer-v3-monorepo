// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IRouterSwap } from "./IRouterSwap.sol";
import { IMevTaxCollector } from "./IMevTaxCollector.sol";

interface IMevRouter is IRouterSwap {
    struct MevRouterParams {
        IMevTaxCollector mevTaxCollector;
        uint256 mevTaxMultiplier;
        uint256 priorityGasThreshold;
    }

    event MevTaxCharged(address pool, uint256 mevTax);

    function isMevTaxEnabled() external view returns (bool isMevTaxEnabled);

    function enableMevTax() external;

    function disableMevTax() external;

    function getMevTaxCollector() external view returns (IMevTaxCollector mevTaxCollector);

    function setMevTaxCollector(IMevTaxCollector mevTaxCollector) external;

    function getMevTaxMultiplier() external view returns (uint256 mevTaxMultiplier);

    function setMevTaxMultiplier(uint256 mevTaxMultiplier) external;

    function getPriorityGasThreshold() external view returns (uint256 priorityGasThreshold);

    function setPriorityGasThreshold(uint256 priorityGasThreshold) external;
}
