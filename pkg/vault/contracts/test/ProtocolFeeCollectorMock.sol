// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../ProtocolFeeCollector.sol";

contract ProtocolFeeCollectorMock is ProtocolFeeCollector {
    constructor(IVault vault_) ProtocolFeeCollector(vault_) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getAggregateFeePercentage(
        uint256 protocolFeePercentage,
        uint256 poolCreatorFeePercentage
    ) external pure returns (uint256) {
        return _getAggregateFeePercentage(protocolFeePercentage, poolCreatorFeePercentage);
    }

    function getPoolTokensAndCount(address pool) external view returns (IERC20[] memory tokens, uint256 numTokens) {
        return _getPoolTokensAndCount(pool);
    }
}
