// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { FEE_SCALING_FACTOR } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import {
    SingletonAuthentication
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/SingletonAuthentication.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { VaultGuard } from "./VaultGuard.sol";

contract ProtocolFeeController is
    IProtocolFeeController,
    SingletonAuthentication,
    ReentrancyGuardTransient,
    VaultGuard
{
    using FixedPoint for uint256;
    using SafeERC20 for IERC20;

    /**
     * @dev Instead of storing only the fee in the mapping, also store a flag to indicate whether the fee has been
     * set by governance through a permissioned call. (The fee is stored in 64-bits, so that the struct fits
     * within a single slot.)
     *
     * We know the percentage is an 18-decimal FP value, which only takes 60 bits, so it's guaranteed to fit,
     * and we can do simple casts to truncate the high bits without needed SafeCast.
     *
     * We want to enable permissionless updates for pools, so that it is less onerous to update potentially
     * hundreds of pools if the global protocol fees change. However, we don't want to overwrite pools that
     * have had their fee percentages manually set by the DAO (i.e., after off-chain negotiation and agreement).
     *
     * @param feePercentage The raw swap or yield fee percentage
     * @param isOverride When set, this fee is controlled by governance, and cannot be changed permissionlessly
     */
    struct PoolFeeConfig {
        uint64 feePercentage;
        bool isOverride;
    }

    // Maximum protocol swap fee percentage. 1e18 corresponds to a 100% fee.
    uint256 internal constant _MAX_PROTOCOL_SWAP_FEE_PERCENTAGE = 50e16; // 50%

    // Maximum protocol yield fee percentage.
    uint256 internal constant _MAX_PROTOCOL_YIELD_FEE_PERCENTAGE = 50e16; // 50%

    // Global protocol swap fee.
    uint256 private _globalProtocolSwapFeePercentage;

    // Global protocol yield fee.
    uint256 private _globalProtocolYieldFeePercentage;

    // Store the pool-specific swap fee percentages (the Vault's poolConfigBits stores the aggregate percentage).
    mapping(address => PoolFeeConfig) internal _poolProtocolSwapFeePercentages;

    // Store the pool-specific yield fee percentages (the Vault's poolConfigBits stores the aggregate percentage).
    mapping(address => PoolFeeConfig) internal _poolProtocolYieldFeePercentages;

    // Pool -> address of pool creator (empowered to set pool creator fee percentages, and withdraw creator fees).
    mapping(address => address) internal _poolCreators;

    // Pool -> creator swap fee percentage.
    mapping(address => uint256) internal _poolCreatorSwapFeePercentages;

    // Pool -> creator yield fee percentage.
    mapping(address => uint256) internal _poolCreatorYieldFeePercentages;

    // Pool -> (Token -> fee): Disaggregated protocol fees (from swap and yield), available for withdrawal
    // by governance.
    mapping(address => mapping(IERC20 => uint256)) internal _protocolFeeAmounts;

    // Pool -> (Token -> fee): Disaggregated pool creator fees (from swap and yield), available for withdrawal by
    // the pool creator.
    mapping(address => mapping(IERC20 => uint256)) internal _poolCreatorFeeAmounts;

    // Ensure that the caller is the pool creator.
    modifier onlyPoolCreator(address pool) {
        _ensureCallerIsPoolCreator(pool);
        _;
    }

    modifier withValidSwapFee(uint256 newSwapFeePercentage) {
        if (newSwapFeePercentage > _MAX_PROTOCOL_SWAP_FEE_PERCENTAGE) {
            revert ProtocolSwapFeePercentageTooHigh();
        }
        _;
    }

    modifier withValidYieldFee(uint256 newYieldFeePercentage) {
        if (newYieldFeePercentage > _MAX_PROTOCOL_YIELD_FEE_PERCENTAGE) {
            revert ProtocolYieldFeePercentageTooHigh();
        }
        _;
    }

    // Force collection and disaggregation (e.g., before changing protocol fee percentages)
    modifier withLatestFees(address pool) {
        getVault().collectAggregateFees(pool);
        _;
    }

    constructor(IVault vault_) SingletonAuthentication(vault_) VaultGuard(vault_) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IProtocolFeeController
    function vault() external view returns (IVault) {
        return getVault();
    }

    /// @inheritdoc IProtocolFeeController
    function getGlobalProtocolSwapFeePercentage() external view returns (uint256) {
        return _globalProtocolSwapFeePercentage;
    }

    /// @inheritdoc IProtocolFeeController
    function getGlobalProtocolYieldFeePercentage() external view returns (uint256) {
        return _globalProtocolYieldFeePercentage;
    }

    /// @inheritdoc IProtocolFeeController
    function getPoolProtocolSwapFeeInfo(address pool) external view returns (uint256, bool) {
        PoolFeeConfig memory config = _poolProtocolSwapFeePercentages[pool];

        return (config.feePercentage, config.isOverride);
    }

    /// @inheritdoc IProtocolFeeController
    function getPoolProtocolYieldFeeInfo(address pool) external view returns (uint256, bool) {
        PoolFeeConfig memory config = _poolProtocolYieldFeePercentages[pool];

        return (config.feePercentage, config.isOverride);
    }

    /// @inheritdoc IProtocolFeeController
    function getProtocolFeeAmounts(address pool) external view returns (uint256[] memory feeAmounts) {
        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);

        feeAmounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            feeAmounts[i] = _protocolFeeAmounts[pool][poolTokens[i]];
        }
    }

    /// @inheritdoc IProtocolFeeController
    function getPoolCreatorFeeAmounts(address pool) external view returns (uint256[] memory feeAmounts) {
        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);

        feeAmounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            feeAmounts[i] = _poolCreatorFeeAmounts[pool][poolTokens[i]];
        }
    }

    /// @inheritdoc IProtocolFeeController
    function computeAggregateFeePercentage(
        uint256 protocolFeePercentage,
        uint256 poolCreatorFeePercentage
    ) external pure returns (uint256) {
        return _computeAggregateFeePercentage(protocolFeePercentage, poolCreatorFeePercentage);
    }

    function _getAggregateFeePercentage(address pool, ProtocolFeeType feeType) internal view returns (uint256) {
        uint256 protocolFeePercentage;
        uint256 poolCreatorFeePercentage;

        if (feeType == ProtocolFeeType.SWAP) {
            protocolFeePercentage = _poolProtocolSwapFeePercentages[pool].feePercentage;
            poolCreatorFeePercentage = _poolCreatorSwapFeePercentages[pool];
        } else {
            protocolFeePercentage = _poolProtocolYieldFeePercentages[pool].feePercentage;
            poolCreatorFeePercentage = _poolCreatorYieldFeePercentages[pool];
        }

        return _computeAggregateFeePercentage(protocolFeePercentage, poolCreatorFeePercentage);
    }

    function _computeAggregateFeePercentage(
        uint256 protocolFeePercentage,
        uint256 poolCreatorFeePercentage
    ) internal pure returns (uint256 aggregateFeePercentage) {
        aggregateFeePercentage =
            protocolFeePercentage +
            protocolFeePercentage.complement().mulDown(poolCreatorFeePercentage);

        // Primary fee percentages are 18-decimal values, stored here in 64 bits, and calculated with full 256-bit
        // precision. However, the resulting aggregate fees are stored in the Vault with 24-bit precision, which
        // corresponds to 0.00001% resolution (i.e., a fee can be 1%, 1.00001%, 1.00002%, but not 1.000005%).
        // Ensure there will be no precision loss in the Vault - which would lead to a discrepancy between the
        // aggregate fee calculated here and that stored in the Vault.
        if ((aggregateFeePercentage / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR != aggregateFeePercentage) {
            revert IVaultErrors.FeePrecisionTooHigh();
        }
    }

    function _ensureCallerIsPoolCreator(address pool) internal view {
        address poolCreator = _poolCreators[pool];

        if (poolCreator == address(0)) {
            revert PoolCreatorNotRegistered(pool);
        }

        if (poolCreator != msg.sender) {
            revert CallerIsNotPoolCreator(msg.sender);
        }
    }

    function _getPoolTokensAndCount(address pool) internal view returns (IERC20[] memory tokens, uint256 numTokens) {
        tokens = getVault().getPoolTokens(pool);
        numTokens = tokens.length;
    }

    /// @inheritdoc IProtocolFeeController
    function updateProtocolSwapFeePercentage(address pool) external withLatestFees(pool) {
        PoolFeeConfig memory feeConfig = _poolProtocolSwapFeePercentages[pool];
        uint256 globalProtocolSwapFee = _globalProtocolSwapFeePercentage;

        if (feeConfig.isOverride == false && globalProtocolSwapFee != feeConfig.feePercentage) {
            _updatePoolSwapFeePercentage(pool, globalProtocolSwapFee, false);
        }
    }

    /// @inheritdoc IProtocolFeeController
    function updateProtocolYieldFeePercentage(address pool) external withLatestFees(pool) {
        PoolFeeConfig memory feeConfig = _poolProtocolYieldFeePercentages[pool];
        uint256 globalProtocolYieldFee = _globalProtocolYieldFeePercentage;

        if (feeConfig.isOverride == false && globalProtocolYieldFee != feeConfig.feePercentage) {
            _updatePoolYieldFeePercentage(pool, globalProtocolYieldFee, false);
        }
    }

    /***************************************************************************
                                Permissioned Functions
    ***************************************************************************/

    /// @inheritdoc IProtocolFeeController
    function registerPool(
        address pool,
        address poolCreator,
        bool protocolFeeExempt
    ) external onlyVault returns (uint256 aggregateSwapFeePercentage, uint256 aggregateYieldFeePercentage) {
        _poolCreators[pool] = poolCreator;

        // Set local storage of the actual percentages for the pool (default to global).
        aggregateSwapFeePercentage = protocolFeeExempt ? 0 : _globalProtocolSwapFeePercentage;
        aggregateYieldFeePercentage = protocolFeeExempt ? 0 : _globalProtocolYieldFeePercentage;

        // `isOverride` is true if the pool is protocol fee exempt; otherwise, default to false.
        // If exempt, this pool cannot be updated to the current global percentage permissionlessly.
        _poolProtocolSwapFeePercentages[pool] = PoolFeeConfig({
            feePercentage: uint64(aggregateSwapFeePercentage),
            isOverride: protocolFeeExempt
        });
        _poolProtocolYieldFeePercentages[pool] = PoolFeeConfig({
            feePercentage: uint64(aggregateYieldFeePercentage),
            isOverride: protocolFeeExempt
        });
    }

    enum ProtocolFeeType {
        SWAP,
        YIELD
    }

    /// @inheritdoc IProtocolFeeController
    function receiveAggregateFees(
        address pool,
        uint256[] memory swapFeeAmounts,
        uint256[] memory yieldFeeAmounts
    ) external onlyVault {
        _receiveAggregateFees(pool, ProtocolFeeType.SWAP, swapFeeAmounts);
        _receiveAggregateFees(pool, ProtocolFeeType.YIELD, yieldFeeAmounts);
    }

    function _receiveAggregateFees(address pool, ProtocolFeeType feeType, uint256[] memory feeAmounts) private {
        // There are two cases when we don't need to split fees (in which case we can save gas and avoid rounding
        // errors by skipping calculations) if either the protocol or pool creator fee percentage is zero.

        uint256 protocolFeePercentage = feeType == ProtocolFeeType.SWAP
            ? _poolProtocolSwapFeePercentages[pool].feePercentage
            : _poolProtocolYieldFeePercentages[pool].feePercentage;

        uint256 poolCreatorFeePercentage = feeType == ProtocolFeeType.SWAP
            ? _poolCreatorSwapFeePercentages[pool]
            : _poolCreatorYieldFeePercentages[pool];

        uint256 aggregateFeePercentage;

        bool needToSplitFees = poolCreatorFeePercentage > 0 && protocolFeePercentage > 0;
        if (needToSplitFees) {
            // Calculate once, outside the loop.
            aggregateFeePercentage = _computeAggregateFeePercentage(protocolFeePercentage, poolCreatorFeePercentage);
        }

        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);
        for (uint256 i = 0; i < numTokens; ++i) {
            if (feeAmounts[i] > 0) {
                IERC20 token = poolTokens[i];

                token.safeTransferFrom(address(getVault()), address(this), feeAmounts[i]);

                // It should be easier for off-chain processes to handle two events, rather than parsing the type
                // out of a single event.
                if (feeType == ProtocolFeeType.SWAP) {
                    emit ProtocolSwapFeeCollected(pool, token, feeAmounts[i]);
                } else {
                    emit ProtocolYieldFeeCollected(pool, token, feeAmounts[i]);
                }

                if (needToSplitFees) {
                    uint256 totalVolume = feeAmounts[i].divUp(aggregateFeePercentage);
                    uint256 protocolPortion = totalVolume.mulUp(protocolFeePercentage);

                    _protocolFeeAmounts[pool][token] += protocolPortion;
                    _poolCreatorFeeAmounts[pool][token] += feeAmounts[i] - protocolPortion;
                } else {
                    // If we don't need to split, one of them must be zero.
                    if (poolCreatorFeePercentage == 0) {
                        _protocolFeeAmounts[pool][token] += feeAmounts[i];
                    } else {
                        _poolCreatorFeeAmounts[pool][token] += feeAmounts[i];
                    }
                }
            }
        }
    }

    /// @inheritdoc IProtocolFeeController
    function setGlobalProtocolSwapFeePercentage(
        uint256 newProtocolSwapFeePercentage
    ) external withValidSwapFee(newProtocolSwapFeePercentage) authenticate {
        _globalProtocolSwapFeePercentage = newProtocolSwapFeePercentage;

        emit GlobalProtocolSwapFeePercentageChanged(newProtocolSwapFeePercentage);
    }

    /// @inheritdoc IProtocolFeeController
    function setGlobalProtocolYieldFeePercentage(
        uint256 newProtocolYieldFeePercentage
    ) external withValidYieldFee(newProtocolYieldFeePercentage) authenticate {
        _globalProtocolYieldFeePercentage = newProtocolYieldFeePercentage;

        emit GlobalProtocolYieldFeePercentageChanged(newProtocolYieldFeePercentage);
    }

    /// @inheritdoc IProtocolFeeController
    function setProtocolSwapFeePercentage(
        address pool,
        uint256 newProtocolSwapFeePercentage
    ) external withValidSwapFee(newProtocolSwapFeePercentage) withLatestFees(pool) authenticate {
        _updatePoolSwapFeePercentage(pool, newProtocolSwapFeePercentage, true);
    }

    /// @inheritdoc IProtocolFeeController
    function setProtocolYieldFeePercentage(
        address pool,
        uint256 newProtocolYieldFeePercentage
    ) external withValidYieldFee(newProtocolYieldFeePercentage) withLatestFees(pool) authenticate {
        _updatePoolYieldFeePercentage(pool, newProtocolYieldFeePercentage, true);
    }

    /// @inheritdoc IProtocolFeeController
    function setPoolCreatorSwapFeePercentage(
        address pool,
        uint256 poolCreatorSwapFeePercentage
    ) external onlyPoolCreator(pool) {
        _setPoolCreatorFeePercentage(pool, poolCreatorSwapFeePercentage, ProtocolFeeType.SWAP);
    }

    /// @inheritdoc IProtocolFeeController
    function setPoolCreatorYieldFeePercentage(
        address pool,
        uint256 poolCreatorYieldFeePercentage
    ) external onlyPoolCreator(pool) {
        _setPoolCreatorFeePercentage(pool, poolCreatorYieldFeePercentage, ProtocolFeeType.YIELD);
    }

    function _setPoolCreatorFeePercentage(
        address pool,
        uint256 poolCreatorFeePercentage,
        ProtocolFeeType feeType
    ) private {
        if (poolCreatorFeePercentage > FixedPoint.ONE) {
            revert PoolCreatorFeePercentageTooHigh();
        }

        // Force collection of fees at existing rate.
        getVault().collectAggregateFees(pool);

        // Need to set locally, and update aggregate percentage in the vault.
        if (feeType == ProtocolFeeType.SWAP) {
            _poolCreatorSwapFeePercentages[pool] = poolCreatorFeePercentage;

            getVault().updateAggregateSwapFeePercentage(pool, _getAggregateFeePercentage(pool, ProtocolFeeType.SWAP));

            emit PoolCreatorSwapFeePercentageChanged(pool, poolCreatorFeePercentage);
        } else {
            _poolCreatorYieldFeePercentages[pool] = poolCreatorFeePercentage;

            getVault().updateAggregateYieldFeePercentage(pool, _getAggregateFeePercentage(pool, ProtocolFeeType.YIELD));

            emit PoolCreatorYieldFeePercentageChanged(pool, poolCreatorFeePercentage);
        }
    }

    /// @inheritdoc IProtocolFeeController
    function withdrawProtocolFees(address pool, address recipient) external authenticate {
        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);

        for (uint256 i = 0; i < numTokens; ++i) {
            IERC20 token = poolTokens[i];

            uint256 amountToWithdraw = _protocolFeeAmounts[pool][token];
            if (amountToWithdraw > 0) {
                _protocolFeeAmounts[pool][token] = 0;
                token.safeTransfer(recipient, amountToWithdraw);
            }
        }
    }

    /// @inheritdoc IProtocolFeeController
    function withdrawPoolCreatorFees(address pool, address recipient) external onlyPoolCreator(pool) {
        _withdrawPoolCreatorFees(pool, recipient);
    }

    /// @inheritdoc IProtocolFeeController
    function withdrawPoolCreatorFees(address pool) external {
        _withdrawPoolCreatorFees(pool, _poolCreators[pool]);
    }

    function _withdrawPoolCreatorFees(address pool, address recipient) private {
        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);

        for (uint256 i = 0; i < numTokens; ++i) {
            IERC20 token = poolTokens[i];

            uint256 amountToWithdraw = _poolCreatorFeeAmounts[pool][token];
            if (amountToWithdraw > 0) {
                _poolCreatorFeeAmounts[pool][token] = 0;
                token.safeTransfer(recipient, amountToWithdraw);
            }
        }
    }

    /// @dev Common code shared between set/update. `isOverride` will be true if governance is setting the percentage.
    function _updatePoolSwapFeePercentage(address pool, uint256 newProtocolSwapFeePercentage, bool isOverride) private {
        // Update local storage of the raw percentage
        _poolProtocolSwapFeePercentages[pool] = PoolFeeConfig({
            feePercentage: uint64(newProtocolSwapFeePercentage),
            isOverride: isOverride
        });
        // Update the resulting aggregate swap fee value in the Vault (PoolConfig).
        getVault().updateAggregateSwapFeePercentage(pool, _getAggregateFeePercentage(pool, ProtocolFeeType.SWAP));

        emit ProtocolSwapFeePercentageChanged(pool, newProtocolSwapFeePercentage);
    }

    /// @dev Common code shared between set/update. `isOverride` will be true if governance is setting the percentage.
    function _updatePoolYieldFeePercentage(
        address pool,
        uint256 newProtocolYieldFeePercentage,
        bool isOverride
    ) private {
        // Update local storage of the raw percentage
        _poolProtocolYieldFeePercentages[pool] = PoolFeeConfig({
            feePercentage: uint64(newProtocolYieldFeePercentage),
            isOverride: isOverride
        });
        // Update the resulting aggregate yield fee value in the Vault (PoolConfig).
        getVault().updateAggregateYieldFeePercentage(pool, _getAggregateFeePercentage(pool, ProtocolFeeType.YIELD));

        emit ProtocolYieldFeePercentageChanged(pool, newProtocolYieldFeePercentage);
    }
}
