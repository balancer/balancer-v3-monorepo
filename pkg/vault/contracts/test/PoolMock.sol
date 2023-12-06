// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ERC20PoolToken } from "@balancer-labs/v3-solidity-utils/contracts/token/ERC20PoolToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { PoolConfigBits, PoolConfigLib } from "../lib/PoolConfigLib.sol";
import { PoolFactoryMock } from "./PoolFactoryMock.sol";
import { BasePool } from "../BasePool.sol";

contract PoolMock is BasePool {
    using FixedPoint for uint256;

    uint256 public constant MIN_INIT_BPT = 1e6;

    bool public failOnAfterSwapCallback;
    bool public failOnBeforeAddLiquidity;
    bool public failOnAfterAddLiquidity;
    bool public failOnBeforeRemoveLiquidity;
    bool public failOnAfterRemoveLiquidity;

    // Amounts in are multiplied by the multiplier, amounts out are divided by it
    uint256 private _multiplier = FixedPoint.ONE;

    constructor(
        IVault vault,
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders,
        bool registerPool,
        uint256 pauseWindowDuration,
        address pauseManager
    ) BasePool(vault, name, symbol) {
        if (registerPool) {
            PoolFactoryMock factory = new PoolFactoryMock(vault, pauseWindowDuration);

            factory.registerPool(
                address(this),
                tokens,
                rateProviders,
                pauseManager,
                PoolConfigBits.wrap(0).toPoolConfig().callbacks,
                PoolConfigBits.wrap(bytes32(type(uint256).max)).toPoolConfig().liquidityManagement
            );
        }
    }

    function onInitialize(uint256[] memory exactAmountsIn, bytes memory) external pure override returns (uint256) {
        return (MIN_INIT_BPT > exactAmountsIn[0] ? MIN_INIT_BPT : exactAmountsIn[0]);
    }

    function getInvariant(uint256[] memory balances) external pure returns (uint256) {
        return balances[0] > 0 ? balances[0] : balances[1];
    }

    function calcBalance(
        uint256[] memory balances,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external pure returns (uint256 newBalance) {
        return balances[tokenInIndex].mulDown(invariantRatio);
    }

    function setFailOnAfterSwapCallback(bool fail) external {
        failOnAfterSwapCallback = fail;
    }

    function setFailOnBeforeAddLiquidityCallback(bool fail) external {
        failOnBeforeAddLiquidity = fail;
    }

    function setFailOnAfterAddLiquidityCallback(bool fail) external {
        failOnAfterAddLiquidity = fail;
    }

    function setFailOnBeforeRemoveLiquidityCallback(bool fail) external {
        failOnBeforeRemoveLiquidity = fail;
    }

    function setFailOnAfterRemoveLiquidityCallback(bool fail) external {
        failOnAfterRemoveLiquidity = fail;
    }

    function setMultiplier(uint256 newMultiplier) external {
        _multiplier = newMultiplier;
    }

    function onAfterSwap(
        IBasePool.AfterSwapParams calldata params,
        uint256 amountCalculated
    ) external view override returns (bool success) {
        return params.tokenIn != params.tokenOut && amountCalculated > 0 && !failOnAfterSwapCallback;
    }

    function onSwap(IBasePool.SwapParams calldata params) external view override returns (uint256 amountCalculated) {
        return
            params.kind == IVault.SwapKind.GIVEN_IN
                ? params.amountGivenScaled18.mulDown(_multiplier)
                : params.amountGivenScaled18.divDown(_multiplier);
    }

    // Liquidity lifecycle callbacks

    function onBeforeAddLiquidity(
        address,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external view override returns (bool) {
        return !failOnBeforeAddLiquidity;
    }

    function onBeforeRemoveLiquidity(
        address,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external view override returns (bool) {
        return !failOnBeforeRemoveLiquidity;
    }

    function onAfterAddLiquidity(
        address,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external view override returns (bool) {
        return !failOnAfterAddLiquidity;
    }

    function onAfterRemoveLiquidity(
        address,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external view override returns (bool) {
        return !failOnAfterRemoveLiquidity;
    }

    function onAddLiquidityCustom(
        address,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        uint256[] memory,
        bytes memory userData
    ) external pure override returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) {
        amountsIn = maxAmountsIn;
        bptAmountOut = minBptAmountOut;
        returnData = userData;
    }

    function onRemoveLiquiditySingleTokenExactIn(
        address,
        uint256 tokenOutIndex,
        uint256,
        uint256[] memory currentBalances
    ) external pure override returns (uint256 amountOut) {
        amountOut = currentBalances[tokenOutIndex];
    }

    function onRemoveLiquidityCustom(
        address,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        uint256[] memory,
        bytes memory userData
    ) external pure override returns (uint256, uint256[] memory, bytes memory) {
        return (maxBptAmountIn, minAmountsOut, userData);
    }

    /// @dev Even though pools do not handle scaling, we still need this for the tests.
    function getDecimalScalingFactors() external view returns (uint256[] memory scalingFactors) {
        IERC20[] memory tokens = _vault.getPoolTokens(address(this));
        scalingFactors = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            scalingFactors[i] = ScalingHelpers.computeScalingFactor(tokens[i]);
        }
    }
}
