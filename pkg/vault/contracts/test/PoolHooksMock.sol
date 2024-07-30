// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { RateProviderMock } from "./RateProviderMock.sol";
import { BaseHooks } from "../BaseHooks.sol";

contract PoolHooksMock is BaseHooks {
    using FixedPoint for uint256;
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

    bool public shouldForceHookAdjustedAmounts;
    uint256[] public forcedHookAdjustedAmountsLiquidity;

    bool public changeTokenRateOnBeforeSwapHook;
    bool public changeTokenRateOnBeforeInitialize;
    bool public changeTokenRateOnBeforeAddLiquidity;
    bool public changeTokenRateOnBeforeRemoveLiquidity;

    bool public changePoolBalancesOnBeforeSwapHook;
    bool public changePoolBalancesOnBeforeAddLiquidityHook;
    bool public changePoolBalancesOnBeforeRemoveLiquidityHook;

    bool public shouldSettleDiscount;
    uint256 public hookSwapFeePercentage;
    uint256 public hookSwapDiscountPercentage;
    uint256 public addLiquidityHookFeePercentage;
    uint256 public addLiquidityHookDiscountPercentage;
    uint256 public removeLiquidityHookFeePercentage;
    uint256 public removeLiquidityHookDiscountPercentage;

    bool public swapReentrancyHookActive;
    address private _swapHookContract;
    bytes private _swapHookCalldata;

    RateProviderMock private _rateProvider;
    uint256 private _newTokenRate;
    uint256 private _dynamicSwapFee;
    address private _pool;
    address private _specialSender;
    uint256[] private _newBalancesRaw;

    // Bool created because in some tests the test file is used as router and does not implement getSender.
    bool public shouldIgnoreSavedSender;
    address private _savedSender;

    mapping(address => bool) private _allowedFactories;

    HookFlags private _hookFlags;

    constructor(IVault vault) BaseHooks(vault) {
        shouldSettleDiscount = true;
    }

    function onRegister(
        address factory,
        address,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public view override returns (bool) {
        return _allowedFactories[factory];
    }

    function getHookFlags() public view override returns (HookFlags memory) {
        return _hookFlags;
    }

    function setHookFlags(HookFlags memory hookFlags) external {
        _hookFlags = hookFlags;
    }

    function onBeforeInitialize(uint256[] memory, bytes memory) public override returns (bool) {
        if (changeTokenRateOnBeforeInitialize) {
            _updateTokenRate();
        }

        return !failOnBeforeInitialize;
    }

    function onAfterInitialize(uint256[] memory, uint256, bytes memory) public view override returns (bool) {
        return !failOnAfterInitialize;
    }

    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata params,
        address,
        uint256
    ) public view override returns (bool, uint256) {
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

    function onBeforeSwap(PoolSwapParams calldata params, address) public override returns (bool) {
        if (shouldIgnoreSavedSender == false) {
            _savedSender = IRouterCommon(params.router).getSender();
        }

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

    function onAfterSwap(AfterSwapParams calldata params) public override returns (bool, uint256) {
        // check that actual pool balances match
        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = _vault.getPoolTokenInfo(params.pool);

        uint256[] memory currentLiveBalances = IVaultMock(address(_vault)).getCurrentLiveBalances(params.pool);

        (uint256[] memory scalingFactors, uint256[] memory rates) = _vault.getPoolTokenRates(params.pool);

        for (uint256 i = 0; i < tokens.length; ++i) {
            if (tokens[i] == params.tokenIn) {
                if (params.tokenInBalanceScaled18 != currentLiveBalances[i]) {
                    return (false, params.amountCalculatedRaw);
                }
                uint256 expectedTokenInBalanceRaw = params.tokenInBalanceScaled18.toRawUndoRateRoundDown(
                    scalingFactors[i],
                    rates[i]
                );
                if (expectedTokenInBalanceRaw != balancesRaw[i]) {
                    return (false, params.amountCalculatedRaw);
                }
            } else if (tokens[i] == params.tokenOut) {
                if (params.tokenOutBalanceScaled18 != currentLiveBalances[i]) {
                    return (false, params.amountCalculatedRaw);
                }
                uint256 expectedTokenOutBalanceRaw = params.tokenOutBalanceScaled18.toRawUndoRateRoundDown(
                    scalingFactors[i],
                    rates[i]
                );
                if (expectedTokenOutBalanceRaw != balancesRaw[i]) {
                    return (false, params.amountCalculatedRaw);
                }
            }
        }

        uint256 hookAdjustedAmountCalculatedRaw = params.amountCalculatedRaw;
        if (hookSwapFeePercentage > 0) {
            uint256 hookFee = hookAdjustedAmountCalculatedRaw.mulDown(hookSwapFeePercentage);
            if (params.kind == SwapKind.EXACT_IN) {
                hookAdjustedAmountCalculatedRaw -= hookFee;
                _vault.sendTo(params.tokenOut, address(this), hookFee);
            } else {
                hookAdjustedAmountCalculatedRaw += hookFee;
                _vault.sendTo(params.tokenIn, address(this), hookFee);
            }
        } else if (hookSwapDiscountPercentage > 0) {
            uint256 hookDiscount = hookAdjustedAmountCalculatedRaw.mulDown(hookSwapDiscountPercentage);
            if (params.kind == SwapKind.EXACT_IN) {
                hookAdjustedAmountCalculatedRaw += hookDiscount;
                if (shouldSettleDiscount) {
                    params.tokenOut.transfer(address(_vault), hookDiscount);
                    _vault.settle(params.tokenOut, hookDiscount);
                }
            } else {
                hookAdjustedAmountCalculatedRaw -= hookDiscount;
                if (shouldSettleDiscount) {
                    params.tokenIn.transfer(address(_vault), hookDiscount);
                    _vault.settle(params.tokenIn, hookDiscount);
                }
            }
        }

        return (params.amountCalculatedScaled18 > 0 && !failOnAfterSwapHook, hookAdjustedAmountCalculatedRaw);
    }

    // Liquidity lifecycle hooks

    function onBeforeAddLiquidity(
        address router,
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) public override returns (bool) {
        if (shouldIgnoreSavedSender == false) {
            _savedSender = IRouterCommon(router).getSender();
        }

        if (changeTokenRateOnBeforeAddLiquidity) {
            _updateTokenRate();
        }

        if (changePoolBalancesOnBeforeAddLiquidityHook) {
            _setBalancesInVault();
        }

        return !failOnBeforeAddLiquidity;
    }

    function onBeforeRemoveLiquidity(
        address router,
        address,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public override returns (bool) {
        if (shouldIgnoreSavedSender == false) {
            _savedSender = IRouterCommon(router).getSender();
        }

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
        address pool,
        AddLiquidityKind,
        uint256[] memory,
        uint256[] memory amountsInRaw,
        uint256,
        uint256[] memory,
        bytes memory
    ) public override returns (bool, uint256[] memory hookAdjustedAmountsInRaw) {
        // Forces the hook answer to test HooksConfigLib
        if (shouldForceHookAdjustedAmounts) {
            return (true, forcedHookAdjustedAmountsLiquidity);
        }

        (IERC20[] memory tokens, , , ) = _vault.getPoolTokenInfo(pool);
        hookAdjustedAmountsInRaw = amountsInRaw;

        if (addLiquidityHookFeePercentage > 0) {
            for (uint256 i = 0; i < amountsInRaw.length; i++) {
                uint256 hookFee = amountsInRaw[i].mulDown(addLiquidityHookFeePercentage);
                hookAdjustedAmountsInRaw[i] += hookFee;
                _vault.sendTo(tokens[i], address(this), hookFee);
            }
        } else if (addLiquidityHookDiscountPercentage > 0) {
            for (uint256 i = 0; i < amountsInRaw.length; i++) {
                uint256 hookDiscount = amountsInRaw[i].mulDown(addLiquidityHookDiscountPercentage);
                tokens[i].transfer(address(_vault), hookDiscount);
                _vault.settle(tokens[i], hookDiscount);
                hookAdjustedAmountsInRaw[i] -= hookDiscount;
            }
        }

        return (!failOnAfterAddLiquidity, hookAdjustedAmountsInRaw);
    }

    function onAfterRemoveLiquidity(
        address,
        address pool,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory amountsOutRaw,
        uint256[] memory,
        bytes memory
    ) public override returns (bool, uint256[] memory hookAdjustedAmountsOutRaw) {
        // Forces the hook answer to test HooksConfigLib
        if (shouldForceHookAdjustedAmounts) {
            return (true, forcedHookAdjustedAmountsLiquidity);
        }

        (IERC20[] memory tokens, , , ) = _vault.getPoolTokenInfo(pool);
        hookAdjustedAmountsOutRaw = amountsOutRaw;

        if (removeLiquidityHookFeePercentage > 0) {
            for (uint256 i = 0; i < amountsOutRaw.length; i++) {
                uint256 hookFee = amountsOutRaw[i].mulDown(removeLiquidityHookFeePercentage);
                hookAdjustedAmountsOutRaw[i] -= hookFee;
                _vault.sendTo(tokens[i], address(this), hookFee);
            }
        } else if (removeLiquidityHookDiscountPercentage > 0) {
            for (uint256 i = 0; i < amountsOutRaw.length; i++) {
                uint256 hookDiscount = amountsOutRaw[i].mulDown(removeLiquidityHookDiscountPercentage);
                tokens[i].transfer(address(_vault), hookDiscount);
                _vault.settle(tokens[i], hookDiscount);
                hookAdjustedAmountsOutRaw[i] += hookDiscount;
            }
        }

        return (!failOnAfterRemoveLiquidity, hookAdjustedAmountsOutRaw);
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

    function setShouldSettleDiscount(bool shouldSettleDiscountFlag) external {
        shouldSettleDiscount = shouldSettleDiscountFlag;
    }

    function setHookSwapFeePercentage(uint256 feePercentage) external {
        hookSwapFeePercentage = feePercentage;
    }

    function setHookSwapDiscountPercentage(uint256 discountPercentage) external {
        hookSwapDiscountPercentage = discountPercentage;
    }

    function setAddLiquidityHookFeePercentage(uint256 hookFeePercentage) public {
        addLiquidityHookFeePercentage = hookFeePercentage;
    }

    function setAddLiquidityHookDiscountPercentage(uint256 hookDiscountPercentage) public {
        addLiquidityHookDiscountPercentage = hookDiscountPercentage;
    }

    function setRemoveLiquidityHookFeePercentage(uint256 hookFeePercentage) public {
        removeLiquidityHookFeePercentage = hookFeePercentage;
    }

    function setRemoveLiquidityHookDiscountPercentage(uint256 hookDiscountPercentage) public {
        removeLiquidityHookDiscountPercentage = hookDiscountPercentage;
    }

    function enableForcedHookAdjustedAmountsLiquidity(uint256[] memory hookAdjustedAmountsLiquidity) public {
        shouldForceHookAdjustedAmounts = true;
        forcedHookAdjustedAmountsLiquidity = hookAdjustedAmountsLiquidity;
    }

    function disableForcedHookAdjustedAmounts() public {
        shouldForceHookAdjustedAmounts = false;
    }

    function allowFactory(address factory) external {
        _allowedFactories[factory] = true;
    }

    function denyFactory(address factory) external {
        _allowedFactories[factory] = false;
    }

    function setShouldIgnoreSavedSender(bool value) external {
        shouldIgnoreSavedSender = value;
    }

    function getSavedSender() external view returns (address) {
        return _savedSender;
    }

    /****************************************************************
                           Helpers
    ****************************************************************/
    function _updateTokenRate() private {
        _rateProvider.mockRate(_newTokenRate);
    }

    function _setBalancesInVault() private {
        IERC20[] memory poolTokens = _vault.getPoolTokens(_pool);
        // We don't care about last live balances here, so we just use the same raw balances
        IVaultMock(address(_vault)).manualSetPoolTokensAndBalances(_pool, poolTokens, _newBalancesRaw, _newBalancesRaw);
    }
}
