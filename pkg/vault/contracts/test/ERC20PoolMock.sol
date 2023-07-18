// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import "../ERC20BalancerPoolToken.sol";

contract ERC20PoolMock is ERC20BalancerPoolToken, IBasePool {
    IVault private immutable _vault;

    constructor(
        IVault vault,
        string memory name,
        string memory symbol,
        address factory,
        IERC20[] memory tokens,
        bool registerPool
    ) ERC20BalancerPoolToken(vault, name, symbol) {
        _vault = vault;

        if (registerPool) {
            vault.registerPool(factory, tokens);
        }
    }



    function onAddLiquidity(
        address sender,
        uint256[] memory currentBalances,
        uint256[] memory maxAmountsIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn) {
        emit OnAddLiquidityCalled(sender, currentBalances, maxAmountsIn, userData);

        return maxAmountsIn;
    }

    function onExitPool(
        address sender,
        uint256[] memory currentBalances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut, uint256[] memory dueProtocolFeeAmounts) {
        emit OnExitPoolCalled(
            sender,
            currentBalances,
            lastChangeBlock,
            protocolSwapFeePercentage,
            userData
        );

        (amountsOut, dueProtocolFeeAmounts) = abi.decode(userData, (uint256[], uint256[]));
    }
}
