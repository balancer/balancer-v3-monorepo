// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { BasePool } from "../BasePool.sol";
import { PoolConfigBits, PoolConfigLib } from "../lib/PoolConfigLib.sol";
import { PoolFactoryMock } from "./PoolFactoryMock.sol";

contract PoolMock is BasePool {
    using FixedPoint for uint256;

    uint256 public constant MIN_INIT_BPT = 1e6;

    bool public failOnCallback;

    bytes32 private constant _ALL_BITS_SET = bytes32(type(uint256).max);
    uint256 private immutable _numTokens;

    constructor(
        IVault vault,
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        bool registerPool
    ) BasePool(vault, name, symbol) {
        if (registerPool) {
            PoolFactoryMock factory = new PoolFactoryMock(vault, 365 days);

            factory.registerPool(
                address(this),
                tokens,
                address(0),
                PoolConfigBits.wrap(0).toPoolConfig().callbacks,
                PoolConfigBits.wrap(_ALL_BITS_SET).toPoolConfig().liquidityManagement
            );
        }

        _numTokens = tokens.length;
    }

    function onInitialize(
        uint256[] memory exactScaled18AmountsIn,
        bytes memory
    ) external view onlyVault returns (uint256) {
        return (MIN_INIT_BPT > exactScaled18AmountsIn[0] ? MIN_INIT_BPT : exactScaled18AmountsIn[0]);
    }

    function onAfterAddLiquidity(
        address,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external view override returns (bool) {
        return !failOnCallback;
    }

    function onAfterRemoveLiquidity(
        address,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external view override returns (bool) {
        return !failOnCallback;
    }

    function setFailOnAfterSwap(bool fail) external {
        failOnCallback = fail;
    }

    function onAfterSwap(
        IBasePool.AfterSwapParams calldata,
        uint256 scaled18AmountCalculated
    ) external view override returns (bool success) {
        return scaled18AmountCalculated > 0 && !failOnCallback;
    }

    function onSwap(IBasePool.SwapParams calldata params) external pure override returns (uint256 amountCalculated) {
        return params.scaled18AmountGiven;
    }

    function _getTotalTokens() internal view virtual override returns (uint256) {
        return _numTokens;
    }

    /// @dev Even though pools do not handle scaling, we still need this for the tests.
    function getScalingFactors() external view returns (uint256[] memory scalingFactors) {
        IERC20[] memory tokens = _vault.getPoolTokens(address(this));
        scalingFactors = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            scalingFactors[i] = ScalingHelpers.computeScalingFactor(tokens[i]);
        }
    }

    function onBeforeAddLiquidity(
        address,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external pure override returns (bool) {
        return true;
    }

    function onAddLiquidityUnbalanced(
        address,
        uint256[] memory exactAmountsIn,
        uint256[] memory
    ) external pure override returns (uint256) {
        return exactAmountsIn[0];
    }

    function onAddLiquiditySingleTokenExactOut(
        address,
        uint256,
        uint256,
        uint256[] memory
    ) external pure override returns (uint256) {
        revert CallbackNotImplemented();
    }

    function onAddLiquidityCustom(
        address,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external pure override returns (uint256[] memory, uint256, bytes memory) {
        revert CallbackNotImplemented();
    }

    function onBeforeRemoveLiquidity(
        address,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external pure override returns (bool) {
        return true;
    }

    function onRemoveLiquiditySingleTokenExactIn(
        address,
        uint256,
        uint256,
        uint256[] memory
    ) external pure override returns (uint256) {
        revert CallbackNotImplemented();
    }

    function onRemoveLiquiditySingleTokenExactOut(
        address,
        uint256,
        uint256,
        uint256[] memory
    ) external pure override returns (uint256) {
        revert CallbackNotImplemented();
    }

    function onRemoveLiquidityCustom(
        address,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external pure override returns (uint256, uint256[] memory, bytes memory) {
        revert CallbackNotImplemented();
    }
}
