// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { PoolConfigBits, PoolConfigLib } from "../lib/PoolConfigLib.sol";
import { ERC20FacadeToken } from "../ERC20FacadeToken.sol";

contract ERC20PoolMock is ERC20FacadeToken, IBasePool {
    using FixedPoint for uint256;

    IVault private immutable _vault;
    IERC20[] _tokens;

    bool public failOnHook;

    constructor(
        IVault vault,
        string memory name,
        string memory symbol,
        IERC20[] memory tokens
    ) ERC20FacadeToken(vault, name, symbol) {
        _vault = vault;
        _tokens = tokens;
    }

    function register(address factory) external {
        _vault.registerPool(factory, _tokens, PoolConfigBits.wrap(0).toPoolConfig());
    }

    function onAddLiquidity(
        address,
        uint256[] memory,
        uint256[] memory maxAmountsIn,
        bytes memory
    ) external pure returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        return (maxAmountsIn, maxAmountsIn[0]);
    }

    function onAfterAddLiquidity(
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes memory,
        uint256[] calldata,
        uint256
    ) external view returns (bool) {
        return !failOnHook;
    }

    function onRemoveLiquidity(
        address,
        uint256[] memory,
        uint256[] memory minAmountsOut,
        uint256,
        bytes memory
    ) external pure returns (uint256[] memory amountsOut) {
        return minAmountsOut;
    }

    function onAfterRemoveLiquidity(
        address,
        uint256[] calldata,
        uint256[] calldata,
        uint256,
        bytes memory,
        uint256[] calldata
    ) external view returns (bool) {
        return !failOnHook;
    }

    // Amounts in are multiplied by the multiplier, amounts out are divided by it
    uint256 private _multiplier = FixedPoint.ONE;

    function setFailOnAfterSwap(bool fail) external {
        failOnHook = fail;
    }

    function setMultiplier(uint256 newMultiplier) external {
        _multiplier = newMultiplier;
    }

    function onAfterSwap(
        IBasePool.SwapParams calldata params,
        uint256 amountCalculated
    ) external view override returns (bool success) {
        return params.tokenIn != params.tokenOut && amountCalculated > 0 && !failOnHook;
    }

    function onSwap(IBasePool.SwapParams calldata params) external view override returns (uint256 amountCalculated) {
        return
            params.kind == IVault.SwapKind.GIVEN_IN
                ? params.amountGiven.mulDown(_multiplier)
                : params.amountGiven.divDown(_multiplier);
    }
}
