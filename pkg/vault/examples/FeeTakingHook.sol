// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

contract FeeTakingHook is IPoolHooks {
    IVault immutable vault;

    constructor(IVault _vault) {
        vault = _vault;
    }

    modifier onlyVault() {
        require(msg.sender == address(manager));
        _;
    }

    uint128 public constant LIQUIDITY_FEE = 543; // 543/10000 = 5.43%
    uint128 public constant SWAP_FEE_BIPS = 123; // 123/10000 = 1.23%
    uint128 public constant TOTAL_BIPS = 10000;

    function onAfterSwap(
        IPoolHooks.AfterSwapParams calldata params,
        uint256 amountCalculatedScaled18,
        uint256 amountCalculatedRaw
    ) external override onlyVault returns (bool, uint256) {
        IERC20 feeToken = params.kind == SwapKind.EXACT_IN ? params.tokenOut : params.tokenIn;

        uint256 feeAmountRaw = amountCalculatedRaw* SWAP_FEE_BIPS / TOTAL_BIPS;

        vault.sendTo(feeToken, address(this), feeAmountRaw);

        return (true, amountCalculatedRaw - feeAmountRaw);
    }

    function onAfterRemoveLiquidity(
        address sender,
        uint256 bptAmountIn,
        uint256[] memory amountsOutScaled18,
        uint256[] memory amountsOutRaw,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external override onlyVault returns (bool, uint256[] memory) {
        (TokenConfig[] memory tokenConfig, ,) = vault.getPoolTokenInfo(address(this));

        for (uint256 i; i < amountsOutRaw.length; ++i) {
            uint256 feeAmountRaw = amountsOutRaw[i] * LIQUIDITY_FEE / TOTAL_BIPS;

            if (feeAmountRaw > 0) {
                vault.sendTo(tokenConfig[i].token, address(this), feeAmountRaw);
                amountsOutRaw[i] -= feeAmountRaw;
            }
        }

        return (true, amountsOutRaw);
    }

    function onAfterAddLiquidity(
        address sender,
        uint256[] memory amountsInScaled18,
        uint256[] memory amountsInRaw,
        uint256 bptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external override onlyVault returns (bool, uint256[] memory) {
        (TokenConfig[] memory tokenConfig, ,) = vault.getPoolTokenInfo(address(this));

        for (uint256 i; i < amountsInRaw.length; ++i) {
            uint256 feeAmountRaw = amountsInRaw[i] * LIQUIDITY_FEE / TOTAL_BIPS;

            if (feeAmountRaw > 0) {
                vault.sendTo(tokenConfig[i].token, address(this), feeAmountRaw);
                amountsInRaw[i] -= feeAmountRaw;
            }
        }

        return (true, amountsInRaw);
    }
}
