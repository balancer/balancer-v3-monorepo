// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";

import { ProtocolFeeController } from "../ProtocolFeeController.sol";

contract ProtocolFeeControllerMock is ProtocolFeeController {
    constructor(
        IVaultMock vault_,
        uint256 protocolSwapFeePercentage,
        uint256 protocolYieldFeePercentage
    ) ProtocolFeeController(vault_, protocolSwapFeePercentage, protocolYieldFeePercentage) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getPoolTokensAndCount(address pool) external view returns (IERC20[] memory tokens, uint256 numTokens) {
        return _getPoolTokensAndCount(pool);
    }

    function getPoolCreatorInfo(
        address pool
    ) external view returns (address poolCreator, uint256 creatorSwapFeePercentage, uint256 creatorYieldFeePercentage) {
        return (_getPoolCreator(pool), _poolCreatorSwapFeePercentages[pool], _poolCreatorYieldFeePercentages[pool]);
    }

    /// @dev Set pool creator swap fee percentage without any constraints.
    function manualSetPoolCreatorSwapFeePercentage(address pool, uint256 poolCreatorSwapFeePercentage) external {
        _poolCreatorSwapFeePercentages[pool] = poolCreatorSwapFeePercentage;
        IVaultMock(address(_vault)).manualUpdateAggregateSwapFeePercentage(
            pool,
            _getAggregateFeePercentage(pool, ProtocolFeeType.SWAP)
        );
    }
}
