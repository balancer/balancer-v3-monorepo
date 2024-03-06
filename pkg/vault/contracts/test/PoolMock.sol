// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { PoolConfigBits, PoolConfigLib } from "../lib/PoolConfigLib.sol";
import { PoolFactoryMock } from "./PoolFactoryMock.sol";
import { RateProviderMock } from "./RateProviderMock.sol";
import { BalancerPoolToken } from "../BalancerPoolToken.sol";

contract PoolMock is IBasePool, IPoolHooks, IPoolLiquidity, BalancerPoolToken {
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;

    uint256 public constant MIN_INIT_BPT = 1e6;

    bool public failOnAfterInitialize;
    bool public failOnBeforeInitialize;
    bool public failOnBeforeSwapHook;
    bool public failOnAfterSwapHook;
    bool public failOnBeforeAddLiquidity;
    bool public failOnAfterAddLiquidity;
    bool public failOnBeforeRemoveLiquidity;
    bool public failOnAfterRemoveLiquidity;

    bool public changeTokenRateOnBeforeSwapHook;
    bool public changeTokenRateOnBeforeInitialize;
    bool public changeTokenRateOnBeforeAddLiquidity;
    bool public changeTokenRateOnBeforeRemoveLiquidity;

    uint256 private _newTokenRate;
    RateProviderMock _firstTokenRateProvider;

    // Amounts in are multiplied by the multiplier, amounts out are divided by it
    uint256 private _multiplier = FixedPoint.ONE;

    constructor(
        IVault vault,
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokenConfig,
        bool registerPool,
        uint256 pauseWindowDuration,
        address pauseManager
    ) BalancerPoolToken(vault, name, symbol) {
        if (registerPool) {
            PoolFactoryMock factory = new PoolFactoryMock(vault, pauseWindowDuration);

            _firstTokenRateProvider = RateProviderMock(address(tokenConfig[0].rateProvider));

            factory.registerPool(
                address(this),
                tokenConfig,
                pauseManager,
                PoolConfigBits.wrap(0).toPoolConfig().hooks,
                PoolConfigBits.wrap(bytes32(type(uint256).max)).toPoolConfig().liquidityManagement
            );
        }
    }

    function computeInvariant(uint256[] memory balances) public pure returns (uint256) {
        // inv = x + y
        uint256 invariant;
        for (uint256 index = 0; index < balances.length; index++) {
            invariant += balances[index];
        }
        return invariant;
    }

    /// @inheritdoc IBasePool
    function getPoolTokens() public view returns (IERC20[] memory tokens) {
        return getVault().getPoolTokens(address(this));
    }

    function computeBalance(
        uint256[] memory balances,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external pure returns (uint256 newBalance) {
        // inv = x + y
        uint256 invariant = computeInvariant(balances);
        return (balances[tokenInIndex] + invariant.mulDown(invariantRatio)) - invariant;
    }

    function setFailOnAfterInitializeHook(bool fail) external {
        failOnAfterInitialize = fail;
    }

    function setFailOnBeforeInitializeHook(bool fail) external {
        failOnBeforeInitialize = fail;
    }

    function setChangeTokenRateOnBeforeInitializeHook(bool changeRate, uint256 newTokenRate) external {
        changeTokenRateOnBeforeInitialize = changeRate;
        _newTokenRate = newTokenRate;
    }

    function setFailOnBeforeSwapHook(bool fail) external {
        failOnBeforeSwapHook = fail;
    }

    function setChangeTokenRateOnBeforeSwapHook(bool changeRate, uint256 newTokenRate) external {
        changeTokenRateOnBeforeSwapHook = changeRate;
        _newTokenRate = newTokenRate;
    }

    function setFailOnAfterSwapHook(bool fail) external {
        failOnAfterSwapHook = fail;
    }

    function setFailOnBeforeAddLiquidityHook(bool fail) external {
        failOnBeforeAddLiquidity = fail;
    }

    function setChangeTokenRateOnBeforeAddLiquidityHook(bool changeRate, uint256 newTokenRate) external {
        changeTokenRateOnBeforeAddLiquidity = changeRate;
        _newTokenRate = newTokenRate;
    }

    function setFailOnAfterAddLiquidityHook(bool fail) external {
        failOnAfterAddLiquidity = fail;
    }

    function setFailOnBeforeRemoveLiquidityHook(bool fail) external {
        failOnBeforeRemoveLiquidity = fail;
    }

    function setChangeTokenRateOnBeforeRemoveLiquidityHook(bool changeRate, uint256 newTokenRate) external {
        changeTokenRateOnBeforeRemoveLiquidity = changeRate;
        _newTokenRate = newTokenRate;
    }

    function setFailOnAfterRemoveLiquidityHook(bool fail) external {
        failOnAfterRemoveLiquidity = fail;
    }

    function setMultiplier(uint256 newMultiplier) external {
        _multiplier = newMultiplier;
    }

    function onBeforeInitialize(uint256[] memory, bytes memory) external returns (bool) {
        if (changeTokenRateOnBeforeInitialize) {
            _updateTokenRate();
        }

        return !failOnBeforeInitialize;
    }

    function onAfterInitialize(uint256[] memory, uint256, bytes memory) external view returns (bool) {
        return !failOnAfterInitialize;
    }

    function onBeforeSwap(IBasePool.SwapParams calldata) external override returns (bool success) {
        if (changeTokenRateOnBeforeSwapHook) {
            _updateTokenRate();
        }

        return !failOnBeforeSwapHook;
    }

    function onSwap(IBasePool.SwapParams calldata params) external view override returns (uint256 amountCalculated) {
        return
            params.kind == SwapKind.EXACT_IN
                ? params.amountGivenScaled18.mulDown(_multiplier)
                : params.amountGivenScaled18.divDown(_multiplier);
    }

    function onAfterSwap(
        IPoolHooks.AfterSwapParams calldata params,
        uint256 amountCalculatedScaled18
    ) external view override returns (bool success) {
        // check that actual pool balances match
        (IERC20[] memory tokens, , uint256[] memory balancesRaw, uint256[] memory scalingFactors, ) = getVault()
            .getPoolTokenInfo(address(this));
        uint256[] memory rates = getVault().getPoolTokenRates(address(this));

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == params.tokenIn) {
                uint256 expectedTokenInBalanceRaw = params.tokenInBalanceScaled18.toRawUndoRateRoundDown(
                    scalingFactors[i],
                    rates[i]
                );
                if (expectedTokenInBalanceRaw != balancesRaw[i]) {
                    return false;
                }
            } else if (tokens[i] == params.tokenOut) {
                uint256 expectedTokenOutBalanceRaw = params.tokenOutBalanceScaled18.toRawUndoRateRoundDown(
                    scalingFactors[i],
                    rates[i]
                );
                if (expectedTokenOutBalanceRaw != balancesRaw[i]) {
                    return false;
                }
            }
        }

        return amountCalculatedScaled18 > 0 && !failOnAfterSwapHook;
    }

    // Liquidity lifecycle hooks

    function onBeforeAddLiquidity(
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external override returns (bool) {
        if (changeTokenRateOnBeforeAddLiquidity) {
            _updateTokenRate();
        }

        return !failOnBeforeAddLiquidity;
    }

    function onBeforeRemoveLiquidity(
        address,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external override returns (bool) {
        if (changeTokenRateOnBeforeRemoveLiquidity) {
            _updateTokenRate();
        }

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
        uint256[] memory maxAmountsInScaled18,
        uint256 minBptAmountOut,
        uint256[] memory,
        bytes memory userData
    ) external pure override returns (uint256[] memory, uint256, uint256[] memory, bytes memory) {
        return (maxAmountsInScaled18, minBptAmountOut, new uint256[](maxAmountsInScaled18.length), userData);
    }

    function onRemoveLiquidityCustom(
        address,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        uint256[] memory,
        bytes memory userData
    ) external pure override returns (uint256, uint256[] memory, uint256[] memory, bytes memory) {
        return (maxBptAmountIn, minAmountsOut, new uint256[](minAmountsOut.length), userData);
    }

    /// @dev Even though pools do not handle scaling, we still need this for the tests.
    function getDecimalScalingFactors() external view returns (uint256[] memory scalingFactors) {
        IERC20[] memory tokens = getPoolTokens();
        scalingFactors = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            scalingFactors[i] = ScalingHelpers.computeScalingFactor(tokens[i]);
        }
    }

    function _updateTokenRate() private {
        _firstTokenRateProvider.mockRate(_newTokenRate);
    }
}
