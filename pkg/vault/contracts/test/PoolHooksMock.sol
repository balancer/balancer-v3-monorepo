// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { RateProviderMock } from "./RateProviderMock.sol";
import { BasePoolHooks } from "../BasePoolHooks.sol";

contract PoolHooksMock is BasePoolHooks {
    // using FixedPoint for uint256;
    using ScalingHelpers for uint256;

    bool public failOnAfterInitialize;
    bool public failOnBeforeInitialize;
    bool public failOnComputeDynamicSwapFeeHook;
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

    bool public changePoolBalancesOnBeforeSwapHook;
    bool public changePoolBalancesOnBeforeAddLiquidityHook;
    bool public changePoolBalancesOnBeforeRemoveLiquidityHook;

    bool public swapReentrancyHookActive;
    address private _swapHookContract;
    bytes private _swapHookCalldata;

    RateProviderMock private _rateProvider;
    uint256 private _newTokenRate;
    uint256 private _dynamicSwapFee;
    address private _pool;
    address private _specialSender;
    uint256[] private _newBalancesRaw;

    mapping(address => bool) private _allowedFactories;

    HookFlags private _hookFlags;

    constructor(IVault vault) BasePoolHooks(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function onRegister(
        address factory,
        address,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) external view override returns (bool) {
        return _allowedFactories[factory];
    }

    function getHookFlags() external view override returns (HookFlags memory) {
        return _hookFlags;
    }

    function setHookFlags(HookFlags memory hookFlags) external {
        _hookFlags = hookFlags;
    }

    function onBeforeInitialize(uint256[] memory, bytes memory) external override returns (bool) {
        if (changeTokenRateOnBeforeInitialize) {
            _updateTokenRate();
        }

        return !failOnBeforeInitialize;
    }

    function onAfterInitialize(uint256[] memory, uint256, bytes memory) external view override returns (bool) {
        return !failOnAfterInitialize;
    }

    function onComputeDynamicSwapFee(
        IBasePool.PoolSwapParams calldata params,
        uint256
    ) external view override returns (bool, uint256) {
        uint256 finalSwapFee = _dynamicSwapFee;

        if (_specialSender != address(0)) {
            // Check the sender
            address swapper = IRouterCommon(params.router).getSender();
            if (swapper == _specialSender) {
                finalSwapFee = 0;
            }
        }

        return (!failOnComputeDynamicSwapFeeHook, finalSwapFee);
    }

    function onBeforeSwap(IBasePool.PoolSwapParams calldata) external override returns (bool success) {
        if (changeTokenRateOnBeforeSwapHook) {
            _updateTokenRate();
        }

        if (changePoolBalancesOnBeforeSwapHook) {
            _setBalancesInVault();
        }

        if (swapReentrancyHookActive) {
            require(_swapHookContract != address(0), "Hook contract not set");
            require(_swapHookCalldata.length != 0, "Hook calldata is empty");
            swapReentrancyHookActive = false;
            Address.functionCall(_swapHookContract, _swapHookCalldata);
        }

        return !failOnBeforeSwapHook;
    }

    function onAfterSwap(
        IHooks.AfterSwapParams calldata params,
        uint256 amountCalculatedScaled18
    ) external view override returns (bool success) {
        // check that actual pool balances match
        (TokenConfig[] memory tokenConfig, uint256[] memory balancesRaw, uint256[] memory scalingFactors) = _vault
            .getPoolTokenInfo(_pool);

        uint256[] memory currentLiveBalances = IVaultMock(address(_vault)).getCurrentLiveBalances(_pool);

        uint256[] memory rates = _vault.getPoolTokenRates(_pool);

        for (uint256 i = 0; i < tokenConfig.length; ++i) {
            if (tokenConfig[i].token == params.tokenIn) {
                if (params.tokenInBalanceScaled18 != currentLiveBalances[i]) {
                    return false;
                }
                uint256 expectedTokenInBalanceRaw = params.tokenInBalanceScaled18.toRawUndoRateRoundDown(
                    scalingFactors[i],
                    rates[i]
                );
                if (expectedTokenInBalanceRaw != balancesRaw[i]) {
                    return false;
                }
            } else if (tokenConfig[i].token == params.tokenOut) {
                if (params.tokenOutBalanceScaled18 != currentLiveBalances[i]) {
                    return false;
                }
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

        if (changePoolBalancesOnBeforeAddLiquidityHook) {
            _setBalancesInVault();
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

        if (changePoolBalancesOnBeforeRemoveLiquidityHook) {
            _setBalancesInVault();
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

    /***********************************************************
                           Set flags to fail
    ***********************************************************/

    function setFailOnAfterInitializeHook(bool fail) external {
        failOnAfterInitialize = fail;
    }

    function setFailOnBeforeInitializeHook(bool fail) external {
        failOnBeforeInitialize = fail;
    }

    function setFailOnComputeDynamicSwapFeeHook(bool fail) external {
        failOnComputeDynamicSwapFeeHook = fail;
    }

    function setFailOnBeforeSwapHook(bool fail) external {
        failOnBeforeSwapHook = fail;
    }

    function setFailOnAfterSwapHook(bool fail) external {
        failOnAfterSwapHook = fail;
    }

    function setFailOnBeforeAddLiquidityHook(bool fail) external {
        failOnBeforeAddLiquidity = fail;
    }

    function setFailOnAfterAddLiquidityHook(bool fail) external {
        failOnAfterAddLiquidity = fail;
    }

    function setFailOnBeforeRemoveLiquidityHook(bool fail) external {
        failOnBeforeRemoveLiquidity = fail;
    }

    function setFailOnAfterRemoveLiquidityHook(bool fail) external {
        failOnAfterRemoveLiquidity = fail;
    }

    /***********************************************************
                        Set hooks behavior
    ***********************************************************/

    function setChangePoolBalancesOnBeforeSwapHook(bool changeBalances, uint256[] memory newBalancesRaw) external {
        changePoolBalancesOnBeforeSwapHook = changeBalances;
        _newBalancesRaw = newBalancesRaw;
    }

    function setChangePoolBalancesOnBeforeAddLiquidityHook(
        bool changeBalances,
        uint256[] memory newBalancesRaw
    ) external {
        changePoolBalancesOnBeforeAddLiquidityHook = changeBalances;
        _newBalancesRaw = newBalancesRaw;
    }

    function setChangePoolBalancesOnBeforeRemoveLiquidityHook(
        bool changeBalances,
        uint256[] memory newBalancesRaw
    ) external {
        changePoolBalancesOnBeforeRemoveLiquidityHook = changeBalances;
        _newBalancesRaw = newBalancesRaw;
    }

    function setChangeTokenRateOnBeforeInitializeHook(
        bool changeRate,
        RateProviderMock rateProvider,
        uint256 newTokenRate
    ) external {
        changeTokenRateOnBeforeInitialize = changeRate;
        _rateProvider = rateProvider;
        _newTokenRate = newTokenRate;
    }

    function setChangeTokenRateOnBeforeSwapHook(
        bool changeRate,
        RateProviderMock rateProvider,
        uint256 newTokenRate
    ) external {
        changeTokenRateOnBeforeSwapHook = changeRate;
        _rateProvider = rateProvider;
        _newTokenRate = newTokenRate;
    }

    function setChangeTokenRateOnBeforeAddLiquidityHook(
        bool changeRate,
        RateProviderMock rateProvider,
        uint256 newTokenRate
    ) external {
        changeTokenRateOnBeforeAddLiquidity = changeRate;
        _rateProvider = rateProvider;
        _newTokenRate = newTokenRate;
    }

    function setChangeTokenRateOnBeforeRemoveLiquidityHook(
        bool changeRate,
        RateProviderMock rateProvider,
        uint256 newTokenRate
    ) external {
        changeTokenRateOnBeforeRemoveLiquidity = changeRate;
        _rateProvider = rateProvider;
        _newTokenRate = newTokenRate;
    }

    function setSwapReentrancyHookActive(bool _swapReentrancyHookActive) external {
        swapReentrancyHookActive = _swapReentrancyHookActive;
    }

    function setSwapReentrancyHook(address hookContract, bytes calldata data) external {
        _swapHookContract = hookContract;
        _swapHookCalldata = data;
    }

    function setSpecialSender(address sender) external {
        _specialSender = sender;
    }

    function setDynamicSwapFeePercentage(uint256 dynamicSwapFee) external {
        _dynamicSwapFee = dynamicSwapFee;
    }

    function setPool(address pool) external {
        _pool = pool;
    }

    function allowFactory(address factory) external {
        _allowedFactories[factory] = true;
    }

    function denyFactory(address factory) external {
        _allowedFactories[factory] = false;
    }

    /****************************************************************
                           Helpers
    ****************************************************************/
    function _updateTokenRate() private {
        _rateProvider.mockRate(_newTokenRate);
    }

    function _setBalancesInVault() private {
        IERC20[] memory poolTokens = _vault.getPoolTokens(_pool);
        IVaultMock(address(_vault)).manualSetPoolTokenBalances(_pool, poolTokens, _newBalancesRaw);
    }
}
