// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IPoolInitializer {
    function onBeforeInitialize(uint256[] memory exactAmountsIn, bytes memory userData) external returns (bool);

    function onAfterInitialize(
        uint256[] memory exactAmountsIn,
        uint256 bptAmountOut,
        bytes memory userData
    ) external returns (bool);
}
