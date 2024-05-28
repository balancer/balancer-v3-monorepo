// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IProtocolFeeCollector } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeCollector.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import {
    SingletonAuthentication
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/SingletonAuthentication.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

contract ProtocolFeeCollector is IProtocolFeeCollector, SingletonAuthentication, ReentrancyGuardTransient {
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
    uint256 internal constant _MAX_PROTOCOL_YIELD_FEE_PERCENTAGE = 20e16; // 20%

    // Global protocol swap fee.
    uint256 private _globalProtocolSwapFeePercentage;

    // Global protocol yield fee.
    uint256 private _globalProtocolYieldFeePercentage;

    // Store the pool-specific swap fee percentages (the Vault's poolConfig stores the aggregate percentage).
    mapping(address => PoolFeeConfig) internal _poolProtocolSwapFeePercentages;

    // Store the pool-specific yield fee percentages (the Vault's poolConfig stores the aggregate percentage).
    mapping(address => PoolFeeConfig) internal _poolProtocolYieldFeePercentages;

    // Pool -> (Token -> fee): Disaggregated protocol fees (from swap and yield), available for withdrawal
    // by governance.
    mapping(address => mapping(IERC20 => uint256)) internal _aggregateProtocolFeeAmounts;

    // Pool -> (Token -> fee): Disaggregated pool creator fees (from swap and yield), available for withdrawal by
    // the pool creator.
    mapping(address => mapping(IERC20 => uint256)) internal _aggregatePoolCreatorFeeAmounts;

    modifier onlyVault() {
        if (msg.sender != address(getVault())) {
            revert IVaultErrors.SenderIsNotVault(msg.sender);
        }
        _;
    }

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
        getVault().collectProtocolFees(pool);
        _;
    }

    constructor(IVault vault_) SingletonAuthentication(vault_) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IProtocolFeeCollector
    function vault() external view returns (IVault) {
        return getVault();
    }

    /// @inheritdoc IProtocolFeeCollector
    function getGlobalProtocolSwapFeePercentage() external view returns (uint256) {
        return _globalProtocolSwapFeePercentage;
    }

    /// @inheritdoc IProtocolFeeCollector
    function getGlobalProtocolYieldFeePercentage() external view returns (uint256) {
        return _globalProtocolYieldFeePercentage;
    }

    /// @inheritdoc IProtocolFeeCollector
    function getPoolProtocolSwapFeeInfo(address pool) external view returns (uint256, bool) {
        PoolFeeConfig memory config = _poolProtocolSwapFeePercentages[pool];

        return (config.feePercentage, config.isOverride);
    }

    /// @inheritdoc IProtocolFeeCollector
    function getPoolProtocolYieldFeeInfo(address pool) external view returns (uint256, bool) {
        PoolFeeConfig memory config = _poolProtocolYieldFeePercentages[pool];

        return (config.feePercentage, config.isOverride);
    }

    /// @inheritdoc IProtocolFeeCollector
    function getAggregateProtocolFeeAmounts(address pool) public view returns (uint256[] memory feeAmounts) {
        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);

        feeAmounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            feeAmounts[i] = _aggregateProtocolFeeAmounts[pool][poolTokens[i]];
        }
    }

    /// @inheritdoc IProtocolFeeCollector
    function getAggregatePoolCreatorFeeAmounts(address pool) public view returns (uint256[] memory feeAmounts) {
        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);

        feeAmounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            feeAmounts[i] = _aggregatePoolCreatorFeeAmounts[pool][poolTokens[i]];
        }
    }

    /// @inheritdoc IProtocolFeeCollector
    function computeAggregatePercentages(
        address pool,
        uint256 poolCreatorFeePercentage
    ) public view returns (uint256, uint256) {
        // Compute aggregate fee return values.
        return (
            _getAggregateFeePercentage(_poolProtocolSwapFeePercentages[pool].feePercentage, poolCreatorFeePercentage),
            _getAggregateFeePercentage(_poolProtocolYieldFeePercentages[pool].feePercentage, poolCreatorFeePercentage)
        );
    }

    function _ensureCallerIsPoolCreator(address pool) internal view {
        (address poolCreator, ) = getVault().getPoolCreatorInfo(pool);

        if (poolCreator == address(0)) {
            revert PoolCreatorNotRegistered(pool);
        }

        if (poolCreator != msg.sender) {
            revert CallerIsNotPoolCreator(msg.sender);
        }
    }

    /**
     * Note that pool creator fees are calculated based on creatorAndLpFees, and not in totalFees.
     * See example below:
     *
     * tokenOutAmount = 10000; poolSwapFeePct = 10%; protocolFeePct = 40%; creatorFeePct = 60%
     * totalFees = tokenOutAmount * poolSwapFeePct = 10000 * 10% = 1000
     * protocolFees = totalFees * protocolFeePct = 1000 * 40% = 400
     * creatorAndLpFees = totalFees - protocolFees = 1000 - 400 = 600
     * creatorFees = creatorAndLpFees * creatorFeePct = 600 * 60% = 360
     * lpFees (will stay in the pool) = creatorAndLpFees - creatorFees = 600 - 360 = 240
     */
    function _getAggregateFeePercentage(
        uint256 protocolFeePercentage,
        uint256 poolCreatorFeePercentage
    ) internal pure returns (uint256) {
        return protocolFeePercentage + protocolFeePercentage.complement().mulDown(poolCreatorFeePercentage);
    }

    function _getPoolTokensAndCount(address pool) internal view returns (IERC20[] memory tokens, uint256 numTokens) {
        tokens = getVault().getPoolTokens(pool);
        numTokens = tokens.length;
    }

    /// @inheritdoc IProtocolFeeCollector
    function updateProtocolSwapFeePercentage(address pool) external withLatestFees(pool) {
        PoolFeeConfig memory feeConfig = _poolProtocolSwapFeePercentages[pool];
        uint256 globalProtocolSwapFee = _globalProtocolSwapFeePercentage;

        if (feeConfig.isOverride == false && globalProtocolSwapFee != feeConfig.feePercentage) {
            (, uint256 poolCreatorFeePercentage) = getVault().getPoolCreatorInfo(pool);

            _updatePoolSwapFeePercentage(pool, globalProtocolSwapFee, poolCreatorFeePercentage, false);
        }
    }

    /// @inheritdoc IProtocolFeeCollector
    function updateProtocolYieldFeePercentage(address pool) external withLatestFees(pool) {
        PoolFeeConfig memory feeConfig = _poolProtocolYieldFeePercentages[pool];
        uint256 globalProtocolYieldFee = _globalProtocolYieldFeePercentage;

        if (feeConfig.isOverride == false && globalProtocolYieldFee != feeConfig.feePercentage) {
            (, uint256 poolCreatorFeePercentage) = getVault().getPoolCreatorInfo(pool);

            _updatePoolYieldFeePercentage(pool, globalProtocolYieldFee, poolCreatorFeePercentage, false);
        }
    }

    /***************************************************************************
                                Permissioned Functions
    ***************************************************************************/

    /// @inheritdoc IProtocolFeeCollector
    function registerPool(
        address pool,
        bool protocolFeeExempt
    )
        public
        onlyVault
        returns (uint256 aggregateProtocolSwapFeePercentage, uint256 aggregateProtocolYieldFeePercentage)
    {
        // Set local storage of the actual percentages for the pool (default to global).
        aggregateProtocolSwapFeePercentage = protocolFeeExempt ? 0 : _globalProtocolSwapFeePercentage;
        aggregateProtocolYieldFeePercentage = protocolFeeExempt ? 0 : _globalProtocolYieldFeePercentage;

        // `isOverride` is true if the pool is protocol fee exempt; otherwise, default to false.
        // If exempt, this pool cannot be updated to the current global percentage permissionlessly.
        _poolProtocolSwapFeePercentages[pool] = PoolFeeConfig({
            feePercentage: uint64(aggregateProtocolSwapFeePercentage),
            isOverride: protocolFeeExempt
        });
        _poolProtocolYieldFeePercentages[pool] = PoolFeeConfig({
            feePercentage: uint64(aggregateProtocolYieldFeePercentage),
            isOverride: protocolFeeExempt
        });
    }

    enum ProtocolFeeType {
        SWAP,
        YIELD
    }

    /// @inheritdoc IProtocolFeeCollector
    function receiveProtocolFees(
        address pool,
        uint256[] memory swapFeeAmounts,
        uint256[] memory yieldFeeAmounts
    ) external onlyVault {
        (, uint256 poolCreatorFeePercentage) = getVault().getPoolCreatorInfo(pool);

        _receiveProtocolFees(pool, ProtocolFeeType.SWAP, poolCreatorFeePercentage, swapFeeAmounts);
        _receiveProtocolFees(pool, ProtocolFeeType.YIELD, poolCreatorFeePercentage, yieldFeeAmounts);
    }

    function _receiveProtocolFees(
        address pool,
        ProtocolFeeType feeType,
        uint256 poolCreatorFeePercentage,
        uint256[] memory feeAmounts
    ) private {
        // There are two cases when we don't need to split fees (in which case we can save gas and avoid rounding
        // errors by skipping calculations) if either the protocol or pool creator fee percentage is zero.

        uint256 protocolFeePercentage = feeType == ProtocolFeeType.SWAP
            ? _poolProtocolSwapFeePercentages[pool].feePercentage
            : _poolProtocolYieldFeePercentages[pool].feePercentage;
        uint256 aggregateFeePercentage;

        bool needToSplitFees = poolCreatorFeePercentage > 0 && protocolFeePercentage > 0;
        if (needToSplitFees) {
            // Calculate once, outside the loop.
            aggregateFeePercentage = _getAggregateFeePercentage(protocolFeePercentage, poolCreatorFeePercentage);
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

                    _aggregateProtocolFeeAmounts[pool][token] += protocolPortion;
                    _aggregatePoolCreatorFeeAmounts[pool][token] += feeAmounts[i] - protocolPortion;
                } else {
                    // If we don't need to split, one of them must be zero.
                    if (poolCreatorFeePercentage == 0) {
                        _aggregateProtocolFeeAmounts[pool][token] += feeAmounts[i];
                    } else {
                        _aggregatePoolCreatorFeeAmounts[pool][token] += feeAmounts[i];
                    }
                }
            }
        }
    }

    /// @inheritdoc IProtocolFeeCollector
    function setGlobalProtocolSwapFeePercentage(
        uint256 newProtocolSwapFeePercentage
    ) external withValidSwapFee(newProtocolSwapFeePercentage) authenticate {
        _globalProtocolSwapFeePercentage = newProtocolSwapFeePercentage;

        emit GlobalProtocolSwapFeePercentageChanged(newProtocolSwapFeePercentage);
    }

    /// @inheritdoc IProtocolFeeCollector
    function setGlobalProtocolYieldFeePercentage(
        uint256 newProtocolYieldFeePercentage
    ) external withValidYieldFee(newProtocolYieldFeePercentage) authenticate {
        _globalProtocolYieldFeePercentage = newProtocolYieldFeePercentage;

        emit GlobalProtocolYieldFeePercentageChanged(newProtocolYieldFeePercentage);
    }

    /// @inheritdoc IProtocolFeeCollector
    function setProtocolSwapFeePercentage(
        address pool,
        uint256 newProtocolSwapFeePercentage
    ) external withValidSwapFee(newProtocolSwapFeePercentage) withLatestFees(pool) authenticate {
        (, uint256 poolCreatorFeePercentage) = getVault().getPoolCreatorInfo(pool);

        _updatePoolSwapFeePercentage(pool, newProtocolSwapFeePercentage, poolCreatorFeePercentage, true);
    }

    /// @inheritdoc IProtocolFeeCollector
    function setProtocolYieldFeePercentage(
        address pool,
        uint256 newProtocolYieldFeePercentage
    ) external withValidYieldFee(newProtocolYieldFeePercentage) withLatestFees(pool) authenticate {
        (, uint256 poolCreatorFeePercentage) = getVault().getPoolCreatorInfo(pool);

        _updatePoolYieldFeePercentage(pool, newProtocolYieldFeePercentage, poolCreatorFeePercentage, true);
    }

    /// @inheritdoc IProtocolFeeCollector
    function withdrawProtocolFees(address pool, address recipient) external authenticate {
        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);

        for (uint256 i = 0; i < numTokens; ++i) {
            IERC20 token = poolTokens[i];

            uint256 amountToWithdraw = _aggregateProtocolFeeAmounts[pool][token];
            if (amountToWithdraw > 0) {
                _aggregateProtocolFeeAmounts[pool][token] = 0;
                token.safeTransfer(recipient, amountToWithdraw);
            }
        }
    }

    /// @inheritdoc IProtocolFeeCollector
    function withdrawPoolCreatorFees(address pool, address recipient) external onlyPoolCreator(pool) {
        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);

        for (uint256 i = 0; i < numTokens; ++i) {
            IERC20 token = poolTokens[i];

            uint256 amountToWithdraw = _aggregatePoolCreatorFeeAmounts[pool][token];
            if (amountToWithdraw > 0) {
                _aggregatePoolCreatorFeeAmounts[pool][token] = 0;
                token.safeTransfer(recipient, amountToWithdraw);
            }
        }
    }

    /// @dev Common code shared between set/update. `isOverride` will be true if governance is setting the percentage.
    function _updatePoolSwapFeePercentage(
        address pool,
        uint256 newProtocolSwapFeePercentage,
        uint256 poolCreatorFeePercentage,
        bool isOverride
    ) private {
        // Update local storage of the raw percentage
        _poolProtocolSwapFeePercentages[pool] = PoolFeeConfig({
            feePercentage: uint64(newProtocolSwapFeePercentage),
            isOverride: isOverride
        });
        // Update the resulting aggregate swap fee value in the Vault (PoolConfig).
        getVault().updateAggregateSwapFeePercentage(
            pool,
            _getAggregateFeePercentage(newProtocolSwapFeePercentage, poolCreatorFeePercentage)
        );

        emit ProtocolSwapFeePercentageChanged(pool, newProtocolSwapFeePercentage);
    }

    /// @dev Common code shared between set/update. `isOverride` will be true if governance is setting the percentage.
    function _updatePoolYieldFeePercentage(
        address pool,
        uint256 newProtocolYieldFeePercentage,
        uint256 poolCreatorFeePercentage,
        bool isOverride
    ) private {
        // Update local storage of the raw percentage
        _poolProtocolYieldFeePercentages[pool] = PoolFeeConfig({
            feePercentage: uint64(newProtocolYieldFeePercentage),
            isOverride: isOverride
        });
        // Update the resulting aggregate yield fee value in the Vault (PoolConfig).
        getVault().updateAggregateYieldFeePercentage(
            pool,
            _getAggregateFeePercentage(newProtocolYieldFeePercentage, poolCreatorFeePercentage)
        );

        emit ProtocolYieldFeePercentageChanged(pool, newProtocolYieldFeePercentage);
    }
}
