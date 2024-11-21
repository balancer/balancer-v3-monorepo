// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { FEE_SCALING_FACTOR, MAX_FEE_PERCENTAGE } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { SingletonAuthentication } from "./SingletonAuthentication.sol";
import { VaultGuard } from "./VaultGuard.sol";

/**
 * @notice Helper contract to manage protocol and creator fees outside the Vault.
 * @dev This contract stores global default protocol swap and yield fees, and also tracks the values of those fees
 * for each pool (the `PoolFeeConfig` described below). Protocol fees can always be overwritten by governance, but
 * pool creator fees are controlled by the registered poolCreator (see `PoolRoleAccounts`).
 *
 * The Vault stores a single aggregate percentage for swap and yield fees; only this `ProtocolFeeController` knows
 * the component fee percentages, and how to compute the aggregate from the components. This is done for performance
 * reasons, to minimize gas on the critical path, as this way the Vault simply applies a single "cut", and stores the
 * fee amounts separately from the pool balances.
 *
 * The pool creator fees are "net" protocol fees, meaning the protocol fee is taken first, and the pool creator fee
 * percentage is applied to the remainder. Essentially, the protocol is paid first, then the remainder is divided
 * between the pool creator and the LPs.
 *
 * There is a permissionless function (`collectAggregateFees`) that transfers these tokens from the Vault to this
 * contract, and distributes them between the protocol and pool creator, after which they can be withdrawn at any
 * time by governance and the pool creator, respectively.
 *
 * Protocol fees can be zero in some cases (e.g., the token is registered as exempt), and pool creator fees are zero
 * if there is no creator role address defined. Protocol fees are capped at a maximum percentage (50%); pool creator
 * fees are computed "net" protocol fees, so they can be any value from 0 to 100%. Any combination is possible.
 * A protocol-fee-exempt pool with a 100% pool creator fee would send all fees to the creator. If there is no pool
 * creator, a pool with a 50% protocol fee would divide the fees evenly between the protocol and LPs.
 *
 * This contract is deployed with the Vault, but can be changed by governance.
 */
contract ProtocolFeeController is
    IProtocolFeeController,
    SingletonAuthentication,
    ReentrancyGuardTransient,
    VaultGuard
{
    using FixedPoint for uint256;
    using SafeERC20 for IERC20;
    using SafeCast for *;

    enum ProtocolFeeType {
        SWAP,
        YIELD
    }

    /**
     * @notice Fee configuration stored in the swap and yield fee mappings.
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

    // Maximum protocol swap fee percentage. FixedPoint.ONE corresponds to a 100% fee.
    uint256 public constant MAX_PROTOCOL_SWAP_FEE_PERCENTAGE = 50e16; // 50%

    // Maximum protocol yield fee percentage.
    uint256 public constant MAX_PROTOCOL_YIELD_FEE_PERCENTAGE = 50e16; // 50%

    // Maximum pool creator (swap, yield) fee percentage.
    uint256 public constant MAX_CREATOR_FEE_PERCENTAGE = 99.999e16; // 99.999%

    // Global protocol swap fee.
    uint256 private _globalProtocolSwapFeePercentage;

    // Global protocol yield fee.
    uint256 private _globalProtocolYieldFeePercentage;

    // Store the pool-specific swap fee percentages (the Vault's poolConfigBits stores the aggregate percentage).
    mapping(address pool => PoolFeeConfig swapFeeConfig) internal _poolProtocolSwapFeePercentages;

    // Store the pool-specific yield fee percentages (the Vault's poolConfigBits stores the aggregate percentage).
    mapping(address pool => PoolFeeConfig yieldFeeConfig) internal _poolProtocolYieldFeePercentages;

    // Pool creators for each pool (empowered to set pool creator fee percentages, and withdraw creator fees).
    mapping(address pool => address poolCreator) internal _poolCreators;

    // Pool creator swap fee percentages for each pool.
    mapping(address pool => uint256 poolCreatorSwapFee) internal _poolCreatorSwapFeePercentages;

    // Pool creator yield fee percentages for each pool.
    mapping(address pool => uint256 poolCreatorYieldFee) internal _poolCreatorYieldFeePercentages;

    // Disaggregated protocol fees (from swap and yield), available for withdrawal by governance.
    mapping(address pool => mapping(IERC20 poolToken => uint256 feeAmount)) internal _protocolFeeAmounts;

    // Disaggregated pool creator fees (from swap and yield), available for withdrawal by the pool creator.
    mapping(address pool => mapping(IERC20 poolToken => uint256 feeAmount)) internal _poolCreatorFeeAmounts;

    // Ensure that the caller is the pool creator.
    modifier onlyPoolCreator(address pool) {
        _ensureCallerIsPoolCreator(pool);
        _;
    }

    // Validate the swap fee percentage against the maximum.
    modifier withValidSwapFee(uint256 newSwapFeePercentage) {
        if (newSwapFeePercentage > MAX_PROTOCOL_SWAP_FEE_PERCENTAGE) {
            revert ProtocolSwapFeePercentageTooHigh();
        }
        _ensureValidPrecision(newSwapFeePercentage);
        _;
    }

    // Validate the yield fee percentage against the maximum.
    modifier withValidYieldFee(uint256 newYieldFeePercentage) {
        if (newYieldFeePercentage > MAX_PROTOCOL_YIELD_FEE_PERCENTAGE) {
            revert ProtocolYieldFeePercentageTooHigh();
        }
        _ensureValidPrecision(newYieldFeePercentage);
        _;
    }

    modifier withValidPoolCreatorFee(uint256 newPoolCreatorFeePercentage) {
        if (newPoolCreatorFeePercentage > MAX_CREATOR_FEE_PERCENTAGE) {
            revert PoolCreatorFeePercentageTooHigh();
        }
        _;
    }

    // Force collection and disaggregation (e.g., before changing protocol fee percentages).
    modifier withLatestFees(address pool) {
        collectAggregateFees(pool);
        _;
    }

    constructor(IVault vault_) SingletonAuthentication(vault_) VaultGuard(vault_) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IProtocolFeeController
    function vault() external view returns (IVault) {
        return _vault;
    }

    /// @inheritdoc IProtocolFeeController
    function collectAggregateFees(address pool) public {
        _vault.unlock(abi.encodeCall(ProtocolFeeController.collectAggregateFeesHook, pool));
    }

    /**
     * @dev Copy and zero out the `aggregateFeeAmounts` collected in the Vault accounting, supplying credit
     * for each token. Then have the Vault transfer tokens to this contract, debiting each token for the amount
     * transferred so that the transaction settles when the hook returns.
     */
    function collectAggregateFeesHook(address pool) external onlyVault {
        (uint256[] memory totalSwapFees, uint256[] memory totalYieldFees) = _vault.collectAggregateFees(pool);
        _receiveAggregateFees(pool, totalSwapFees, totalYieldFees);
    }

    /**
     * @notice Settle fee credits from the Vault.
     * @dev This must be called after calling `collectAggregateFees` in the Vault. Note that since charging protocol
     * fees (i.e., distributing tokens between pool and fee balances) occurs in the Vault, but fee collection
     * happens in the ProtocolFeeController, the swap fees reported here may encompass multiple operations. The Vault
     * differentiates between swap and yield fees (since they can have different percentage values); the Controller
     * combines swap and yield fees, then allocates the total between the protocol and pool creator.
     *
     * @param pool The address of the pool on which the swap fees were charged
     * @param swapFeeAmounts An array with the total swap fees collected, sorted in token registration order
     * @param yieldFeeAmounts An array with the total yield fees collected, sorted in token registration order
     */
    function _receiveAggregateFees(
        address pool,
        uint256[] memory swapFeeAmounts,
        uint256[] memory yieldFeeAmounts
    ) internal {
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

                _vault.sendTo(token, address(this), feeAmounts[i]);

                // It should be easier for off-chain processes to handle two events, rather than parsing the type
                // out of a single event.
                if (feeType == ProtocolFeeType.SWAP) {
                    emit ProtocolSwapFeeCollected(pool, token, feeAmounts[i]);
                } else {
                    emit ProtocolYieldFeeCollected(pool, token, feeAmounts[i]);
                }

                if (needToSplitFees) {
                    // The Vault took a single "cut" for the aggregate total percentage (protocol + pool creator) for
                    // this fee type (swap or yield). The first step is to reconstruct this total fee amount. Then we
                    // need to "disaggregate" this total, dividing it between the protocol and pool creator according
                    // to their individual percentages. We do this by computing the protocol portion first, then
                    // assigning the remainder to the pool creator.
                    uint256 totalFeeAmountRaw = feeAmounts[i].divUp(aggregateFeePercentage);
                    uint256 protocolPortion = totalFeeAmountRaw.mulUp(protocolFeePercentage);

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

        // Protocol fee percentages are limited to 24-bit precision for performance reasons (i.e., to fit all the fees
        // in a single slot), and because high precision is not needed. Generally we expect protocol fees set by
        // governance to be simple integers.
        //
        // However, the pool creator fee is entirely controlled by the pool creator, and it is possible to craft a
        // valid pool creator fee percentage that would cause the aggregate fee percentage to fail the precision check.
        // This case should be rare, so we ensure this can't happen by truncating the final value.
        aggregateFeePercentage = (aggregateFeePercentage / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR;
    }

    function _ensureCallerIsPoolCreator(address pool) internal view {
        address poolCreator = _poolCreators[pool];

        if (poolCreator == address(0)) {
            revert PoolCreatorNotRegistered(pool);
        }

        if (poolCreator != msg.sender) {
            revert CallerIsNotPoolCreator(msg.sender, pool);
        }
    }

    function _getPoolTokensAndCount(address pool) internal view returns (IERC20[] memory tokens, uint256 numTokens) {
        tokens = _vault.getPoolTokens(pool);
        numTokens = tokens.length;
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
        // The percentages are 18 decimal floating point numbers, bound between 0 and the max fee (<= FixedPoint.ONE).
        // Since this fits in 64 bits, the SafeCast shouldn't be necessary, and is done out of an abundance of caution.
        _poolProtocolSwapFeePercentages[pool] = PoolFeeConfig({
            feePercentage: aggregateSwapFeePercentage.toUint64(),
            isOverride: protocolFeeExempt
        });
        _poolProtocolYieldFeePercentages[pool] = PoolFeeConfig({
            feePercentage: aggregateYieldFeePercentage.toUint64(),
            isOverride: protocolFeeExempt
        });
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
    ) external authenticate withValidSwapFee(newProtocolSwapFeePercentage) withLatestFees(pool) {
        _updatePoolSwapFeePercentage(pool, newProtocolSwapFeePercentage, true);
    }

    /// @inheritdoc IProtocolFeeController
    function setProtocolYieldFeePercentage(
        address pool,
        uint256 newProtocolYieldFeePercentage
    ) external authenticate withValidYieldFee(newProtocolYieldFeePercentage) withLatestFees(pool) {
        _updatePoolYieldFeePercentage(pool, newProtocolYieldFeePercentage, true);
    }

    /// @inheritdoc IProtocolFeeController
    function setPoolCreatorSwapFeePercentage(
        address pool,
        uint256 poolCreatorSwapFeePercentage
    ) external onlyPoolCreator(pool) withValidPoolCreatorFee(poolCreatorSwapFeePercentage) withLatestFees(pool) {
        _setPoolCreatorFeePercentage(pool, poolCreatorSwapFeePercentage, ProtocolFeeType.SWAP);
    }

    /// @inheritdoc IProtocolFeeController
    function setPoolCreatorYieldFeePercentage(
        address pool,
        uint256 poolCreatorYieldFeePercentage
    ) external onlyPoolCreator(pool) withValidPoolCreatorFee(poolCreatorYieldFeePercentage) withLatestFees(pool) {
        _setPoolCreatorFeePercentage(pool, poolCreatorYieldFeePercentage, ProtocolFeeType.YIELD);
    }

    function _setPoolCreatorFeePercentage(
        address pool,
        uint256 poolCreatorFeePercentage,
        ProtocolFeeType feeType
    ) internal {
        // Need to set locally, and update the aggregate percentage in the Vault.
        if (feeType == ProtocolFeeType.SWAP) {
            _poolCreatorSwapFeePercentages[pool] = poolCreatorFeePercentage;

            // The Vault will also emit an `AggregateSwapFeePercentageChanged` event.
            _vault.updateAggregateSwapFeePercentage(pool, _getAggregateFeePercentage(pool, ProtocolFeeType.SWAP));

            emit PoolCreatorSwapFeePercentageChanged(pool, poolCreatorFeePercentage);
        } else {
            _poolCreatorYieldFeePercentages[pool] = poolCreatorFeePercentage;

            // The Vault will also emit an `AggregateYieldFeePercentageChanged` event.
            _vault.updateAggregateYieldFeePercentage(pool, _getAggregateFeePercentage(pool, ProtocolFeeType.YIELD));

            emit PoolCreatorYieldFeePercentageChanged(pool, poolCreatorFeePercentage);
        }
    }

    /// @inheritdoc IProtocolFeeController
    function withdrawProtocolFees(address pool, address recipient) external authenticate {
        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);

        for (uint256 i = 0; i < numTokens; ++i) {
            IERC20 token = poolTokens[i];

            _withdrawProtocolFees(pool, recipient, token);
        }
    }

    /// @inheritdoc IProtocolFeeController
    function withdrawProtocolFeesForToken(address pool, address recipient, IERC20 token) external authenticate {
        // Revert if the pool is not registered or if the token does not belong to the pool.
        _vault.getPoolTokenCountAndIndexOfToken(pool, token);
        _withdrawProtocolFees(pool, recipient, token);
    }

    function _withdrawProtocolFees(address pool, address recipient, IERC20 token) internal {
        uint256 amountToWithdraw = _protocolFeeAmounts[pool][token];
        if (amountToWithdraw > 0) {
            _protocolFeeAmounts[pool][token] = 0;
            token.safeTransfer(recipient, amountToWithdraw);

            emit ProtocolFeesWithdrawn(pool, token, recipient, amountToWithdraw);
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

                emit PoolCreatorFeesWithdrawn(pool, token, recipient, amountToWithdraw);
            }
        }
    }

    /// @dev Common code shared between set/update. `isOverride` will be true if governance is setting the percentage.
    function _updatePoolSwapFeePercentage(address pool, uint256 newProtocolSwapFeePercentage, bool isOverride) private {
        // Update local storage of the raw percentage.
        //
        // The percentages are 18 decimal floating point numbers, bound between 0 and the max fee (<= FixedPoint.ONE).
        // Since this fits in 64 bits, the SafeCast shouldn't be necessary, and is done out of an abundance of caution.
        _poolProtocolSwapFeePercentages[pool] = PoolFeeConfig({
            feePercentage: newProtocolSwapFeePercentage.toUint64(),
            isOverride: isOverride
        });

        // Update the resulting aggregate swap fee value in the Vault (PoolConfig).
        _vault.updateAggregateSwapFeePercentage(pool, _getAggregateFeePercentage(pool, ProtocolFeeType.SWAP));

        emit ProtocolSwapFeePercentageChanged(pool, newProtocolSwapFeePercentage);
    }

    /// @dev Common code shared between set/update. `isOverride` will be true if governance is setting the percentage.
    function _updatePoolYieldFeePercentage(
        address pool,
        uint256 newProtocolYieldFeePercentage,
        bool isOverride
    ) private {
        // Update local storage of the raw percentage.
        // The percentages are 18 decimal floating point numbers, bound between 0 and the max fee (<= FixedPoint.ONE).
        // Since this fits in 64 bits, the SafeCast shouldn't be necessary, and is done out of an abundance of caution.
        _poolProtocolYieldFeePercentages[pool] = PoolFeeConfig({
            feePercentage: newProtocolYieldFeePercentage.toUint64(),
            isOverride: isOverride
        });

        // Update the resulting aggregate yield fee value in the Vault (PoolConfig).
        _vault.updateAggregateYieldFeePercentage(pool, _getAggregateFeePercentage(pool, ProtocolFeeType.YIELD));

        emit ProtocolYieldFeePercentageChanged(pool, newProtocolYieldFeePercentage);
    }

    function _ensureValidPrecision(uint256 feePercentage) private pure {
        // Primary fee percentages are 18-decimal values, stored here in 64 bits, and calculated with full 256-bit
        // precision. However, the resulting aggregate fees are stored in the Vault with 24-bit precision, which
        // corresponds to 0.00001% resolution (i.e., a fee can be 1%, 1.00001%, 1.00002%, but not 1.000005%).
        // Ensure there will be no precision loss in the Vault - which would lead to a discrepancy between the
        // aggregate fee calculated here and that stored in the Vault.
        if ((feePercentage / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR != feePercentage) {
            revert IVaultErrors.FeePrecisionTooHigh();
        }
    }
}
