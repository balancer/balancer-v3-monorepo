// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseHooks } from "../BaseHooks.sol";

/// @dev Simple hook contract that does nothing but return true on every call.
contract MinimalHooksPoolMock is BaseHooks {
    HookFlags private _hookFlags;

    constructor(IVault vault) BaseHooks(vault) {}

    function onRegister(
        address,
        address,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public pure override returns (bool) {
        return true;
    }

    function getHookFlags() public view override returns (HookFlags memory) {
        return _hookFlags;
    }

    function setHookFlags(HookFlags memory hookFlags) public {
        _hookFlags = hookFlags;
    }

    function onBeforeInitialize(uint256[] memory, bytes memory) public pure override returns (bool) {
        return true;
    }

    function onAfterInitialize(uint256[] memory, uint256, bytes memory) public pure override returns (bool) {
        return true;
    }

    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata,
        address,
        uint256
    ) public pure override returns (bool, uint256) {
        return (true, 0);
    }

    function onBeforeSwap(PoolSwapParams calldata, address) public pure override returns (bool) {
        return true;
    }

    function onAfterSwap(AfterSwapParams calldata params) public pure override returns (bool, uint256) {
        return (true, params.amountCalculatedRaw);
    }

    // Liquidity lifecycle hooks

    function onBeforeAddLiquidity(
        address,
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) public pure override returns (bool) {
        return true;
    }

    function onBeforeRemoveLiquidity(
        address,
        address,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public pure override returns (bool) {
        return true;
    }

    function onAfterAddLiquidity(
        address,
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256[] memory amountsInRaw,
        uint256,
        uint256[] memory,
        bytes memory
    ) public pure override returns (bool, uint256[] memory hookAdjustedAmountsInRaw) {
        return (true, amountsInRaw);
    }

    function onAfterRemoveLiquidity(
        address,
        address,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory amountsOutRaw,
        uint256[] memory,
        bytes memory
    ) public pure override returns (bool, uint256[] memory hookAdjustedAmountsOutRaw) {
        return (true, amountsOutRaw);
    }
}
