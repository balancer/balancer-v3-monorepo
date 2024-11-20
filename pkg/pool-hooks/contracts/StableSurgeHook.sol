// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IStablePool } from "@balancer-labs/v3-interfaces/contracts/pool-stable/IStablePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";
import {
    LiquidityManagement,
    TokenConfig,
    PoolSwapParams,
    HookFlags,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";

import { StableSurgeMedianMath } from "./utils/StableSurgeMedianMath.sol";

/**
 * @notice Hook that charges a fee on trades that push a pool into an imbalanced state beyond a given threshold.
 * @dev Uses the dynamic fee mechanism to apply a directional fee.
 */
contract StableSurgeHook is BaseHooks, VaultGuard, Authentication {
    using FixedPoint for uint256;

    uint256 public constant MAX_SURGE_FEE_PERCENTAGE = 95e16; // 95%

    // The default threshold, above which surging will occur.
    uint256 private immutable _defaultSurgeThresholdPercentage;

    // Store the current threshold for each pool.
    mapping(address pool => uint256 threshold) private _surgeThresholdPercentage;

    /**
     * @notice A new `StableSurgeHookExample` contract has been registered successfully.
     * @dev If the registration fails the call will revert, so there will be no event.
     * @param pool The pool on which the hook was registered
     */
    event StableSurgeHookExampleRegistered(address indexed pool);

    /**
     * @notice The threshold percentage has been changed for a pool in a `StableSurgeHookExample` contract.
     * @dev Note, the initial threshold percentage is set on deployment and an event is emitted.
     * @param pool The pool for which the threshold percentage has been changed
     * @param newSurgeThresholdPercentage The new threshold percentage
     */
    event ThresholdSurgePercentageChanged(address indexed pool, uint256 newSurgeThresholdPercentage);

    /**
     * @notice A new authorizer is set by `setAuthorizer`.
     * @param newAuthorizer The address of the new authorizer
     */
    event AuthorizerChanged(IAuthorizer indexed newAuthorizer);

    /// @notice The threshold must be a valid percentage value.
    error InvalidSurgeThresholdPercentage();

    // Upgradeable contract in charge of setting permissions.
    IAuthorizer internal _authorizer;

    constructor(
        IVault vault,
        uint256 defaultSurgeThresholdPercentage,
        IAuthorizer newAuthorizer
    ) Authentication(bytes32(uint256(uint160(address(vault))))) VaultGuard(vault) {
        _ensureValidPercentage(defaultSurgeThresholdPercentage);

        _defaultSurgeThresholdPercentage = defaultSurgeThresholdPercentage;

        _setAuthorizer(newAuthorizer);
    }

    function setAuthorizer(IAuthorizer newAuthorizer) external authenticate {
        _setAuthorizer(newAuthorizer);
    }

    function _setAuthorizer(IAuthorizer newAuthorizer) internal {
        _authorizer = newAuthorizer;

        emit AuthorizerChanged(newAuthorizer);
    }

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        hookFlags.shouldCallComputeDynamicSwapFee = true;
    }

    /**
     * @notice Getter for the default surge threshold percentage.
     * @return surgeThresholdPercentage The default surge threshold percentage for this hook contract
     */
    function getDefaultSurgeThresholdPercentage() external view returns (uint256) {
        return _defaultSurgeThresholdPercentage;
    }

    /**
     * @notice Getter for the surge threshold percentage for a pool.
     * @param pool The pool for which the surge threshold percentage is requested
     * @return surgeThresholdPercentage The surge threshold percentage for the pool
     */
    function getSurgeThresholdPercentage(address pool) external view returns (uint256) {
        return _surgeThresholdPercentage[pool];
    }

    /// @inheritdoc IHooks
    function onRegister(
        address,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public override onlyVault returns (bool) {
        emit StableSurgeHookExampleRegistered(pool);

        // Initially set the pool threshold to the default (can be changed by the pool swapFeeManager in the future).
        _setSurgeThresholdPercentage(pool, _defaultSurgeThresholdPercentage);

        return true;
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) public view override onlyVault returns (bool, uint256) {
        return (true, getSurgeFeePercentage(params, _surgeThresholdPercentage[pool], staticSwapFeePercentage));
    }

    /**
     * @notice Sets the hook threshold percentage.
     * @dev This function must be permissioned. If the pool does not have a swap fee manager role set, the surge
     * threshold will be effectively immutable, set to the default threshold for this hook contract.
     */
    function setSurgeThresholdPercentage(address pool, uint256 newSurgeThresholdPercentage) external {
        address swapFeeManager = _vault.getPoolRoleAccounts(pool).swapFeeManager;

        if (swapFeeManager == address(0)) {
            if (_canPerform(getActionId(msg.sig), msg.sender, pool) == false) {
                revert SenderNotAllowed();
            }
        } else if (swapFeeManager != msg.sender) {
            revert SenderNotAllowed();
        }

        _ensureValidPercentage(newSurgeThresholdPercentage);

        _setSurgeThresholdPercentage(pool, newSurgeThresholdPercentage);
    }

    /**
     * @notice Calculate the surge fee percentage. If below threshold, return the standard static swap fee percentage.
     * @dev It is public to allow it to be called off-chain.
     * @param params Input parameters for the swap (balances needed)
     * @param surgeThresholdPercentage The current surge threshold percentage for this pool
     * @param staticFeePercentage The static fee percentage for the pool (default if there is no surge)
     */
    function getSurgeFeePercentage(
        PoolSwapParams calldata params,
        uint256 surgeThresholdPercentage,
        uint256 staticFeePercentage
    ) public pure returns (uint256) {
        uint256 numTokens = params.balancesScaled18.length;

        uint256[] memory newBalances = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            newBalances[i] = params.balancesScaled18[i];

            if (i == params.indexIn) {
                newBalances[i] += params.amountGivenScaled18;
            } else if (i == params.indexOut) {
                newBalances[i] -= params.amountGivenScaled18;
            }
        }

        uint256 newTotalImbalance = StableSurgeMedianMath.calculateImbalance(newBalances);

        // If we are balanced, or the balance has improved, do not surge: simply return the regular fee percentage.
        if (newTotalImbalance == 0) {
            return staticFeePercentage;
        }

        uint256 oldTotalImbalance = StableSurgeMedianMath.calculateImbalance(params.balancesScaled18);

        if (newTotalImbalance <= oldTotalImbalance || newTotalImbalance <= surgeThresholdPercentage) {
            return staticFeePercentage;
        }

        // surgeFee = staticFee + (maxFee - staticFee) * (pctImbalance - pctThreshold) / (1 - pctThreshold).
        return
            staticFeePercentage +
            (MAX_SURGE_FEE_PERCENTAGE - staticFeePercentage).mulDown(
                (newTotalImbalance - surgeThresholdPercentage).divDown(surgeThresholdPercentage.complement())
            );
    }

    /// @dev Assumes the percentage value has been externally validated (e.g., with `_ensureValidPercentage`).
    function _setSurgeThresholdPercentage(address pool, uint256 newSurgeThresholdPercentage) private {
        _surgeThresholdPercentage[pool] = newSurgeThresholdPercentage;

        emit ThresholdSurgePercentageChanged(pool, newSurgeThresholdPercentage);
    }

    function _ensureValidPercentage(uint256 percentage) private pure {
        if (percentage > MAX_SURGE_FEE_PERCENTAGE) {
            revert InvalidSurgeThresholdPercentage();
        }
    }

    /// @dev Access control is delegated to the Authorizer.
    function _canPerform(bytes32 actionId, address user) internal view override returns (bool) {
        return _authorizer.canPerform(actionId, user, address(this));
    }

    /// @dev Access control is delegated to the Authorizer. `where` refers to the target contract.
    function _canPerform(bytes32 actionId, address user, address where) internal view returns (bool) {
        return _authorizer.canPerform(actionId, user, where);
    }
}
