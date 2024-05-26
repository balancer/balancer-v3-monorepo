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

    // Maximum protocol swap fee percentage. 1e18 corresponds to a 100% fee.
    uint256 internal constant _MAX_PROTOCOL_SWAP_FEE_PERCENTAGE = 50e16; // 50%

    // Maximum protocol yield fee percentage.
    uint256 internal constant _MAX_PROTOCOL_YIELD_FEE_PERCENTAGE = 20e16; // 20%

    // Global protocol swap fee.
    uint256 private _protocolSwapFeePercentage;

    // Global protocol yield fee.
    uint256 private _protocolYieldFeePercentage;

    // Store the pool-specific swap fee percentages (the Vault's poolConfig stores the aggregate percentage).
    mapping(address => uint256) internal _poolProtocolSwapFeePercentages;

    // Store the pool-specific yield fee percentages (the Vault's poolConfig stores the aggregate percentage).
    mapping(address => uint256) internal _poolProtocolYieldFeePercentages;

    // Pool -> (Token -> fee): Disaggregated protocol fees (from swap and yield), available for withdrawal
    // by governance.
    mapping(address => mapping(IERC20 => uint256)) internal _totalProtocolFeesCollected;

    // Pool -> (Token -> fee): Disaggregated pool creator fees (from swap and yield), available for withdrawal by
    // the pool creator.
    mapping(address => mapping(IERC20 => uint256)) internal _totalPoolCreatorFeesCollected;

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
        return _protocolSwapFeePercentage;
    }

    /// @inheritdoc IProtocolFeeCollector
    function getGlobalProtocolYieldFeePercentage() external view returns (uint256) {
        return _protocolYieldFeePercentage;
    }

    /// @inheritdoc IProtocolFeeCollector
    function getTotalCollectedProtocolFeeAmounts(address pool) public view returns (uint256[] memory feeAmounts) {
        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);

        feeAmounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            feeAmounts[i] = _totalProtocolFeesCollected[pool][poolTokens[i]];
        }
    }

    /// @inheritdoc IProtocolFeeCollector
    function getTotalCollectedPoolCreatorFeeAmounts(address pool) public view returns (uint256[] memory feeAmounts) {
        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);

        feeAmounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            feeAmounts[i] = _totalPoolCreatorFeesCollected[pool][poolTokens[i]];
        }
    }

    /// @inheritdoc IProtocolFeeCollector
    function computeAggregatePercentages(
        address pool,
        uint256 poolCreatorFeePercentage
    ) public view returns (uint256, uint256) {
        // Compute aggregate fee return values.
        return (
            _getAggregateFeePercentage(_poolProtocolSwapFeePercentages[pool], poolCreatorFeePercentage),
            _getAggregateFeePercentage(_poolProtocolYieldFeePercentages[pool], poolCreatorFeePercentage)
        );
    }

    function _ensureCallerIsPoolCreator(address pool) private view {
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
    ) private pure returns (uint256) {
        return protocolFeePercentage + protocolFeePercentage.complement().mulDown(poolCreatorFeePercentage);
    }

    function _getPoolTokensAndCount(address pool) private view returns (IERC20[] memory tokens, uint256 numTokens) {
        tokens = getVault().getPoolTokens(pool);
        numTokens = tokens.length;
    }

    /***************************************************************************
                                Permissioned Functions
    ***************************************************************************/

    /// @inheritdoc IProtocolFeeCollector
    function registerPool(
        address pool
    )
        public
        onlyVault
        returns (uint256 aggregateProtocolSwapFeePercentage, uint256 aggregateProtocolYieldFeePercentage)
    {
        // Set local storage of the actual percentages for the pool (default to global).
        aggregateProtocolSwapFeePercentage = _protocolSwapFeePercentage;
        aggregateProtocolYieldFeePercentage = _protocolYieldFeePercentage;

        _poolProtocolSwapFeePercentages[pool] = aggregateProtocolSwapFeePercentage;
        _poolProtocolYieldFeePercentages[pool] = aggregateProtocolYieldFeePercentage;
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
            ? _poolProtocolSwapFeePercentages[pool]
            : _poolProtocolYieldFeePercentages[pool];
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

                    _totalProtocolFeesCollected[pool][token] += protocolPortion;
                    _totalPoolCreatorFeesCollected[pool][token] += feeAmounts[i] - protocolPortion;
                } else {
                    // If we don't need to split, one of them must be zero.
                    if (poolCreatorFeePercentage == 0) {
                        _totalProtocolFeesCollected[pool][token] += feeAmounts[i];
                    } else {
                        _totalPoolCreatorFeesCollected[pool][token] += feeAmounts[i];
                    }
                }
            }
        }
    }

    /// @inheritdoc IProtocolFeeCollector
    function setGlobalProtocolSwapFeePercentage(
        uint256 newProtocolSwapFeePercentage
    ) external withValidSwapFee(newProtocolSwapFeePercentage) authenticate {
        _protocolSwapFeePercentage = newProtocolSwapFeePercentage;

        emit GlobalProtocolSwapFeePercentageChanged(newProtocolSwapFeePercentage);
    }

    /// @inheritdoc IProtocolFeeCollector
    function setGlobalProtocolYieldFeePercentage(
        uint256 newProtocolYieldFeePercentage
    ) external withValidYieldFee(newProtocolYieldFeePercentage) authenticate {
        _protocolYieldFeePercentage = newProtocolYieldFeePercentage;

        emit GlobalProtocolSwapFeePercentageChanged(newProtocolYieldFeePercentage);
    }

    /// @inheritdoc IProtocolFeeCollector
    function setProtocolSwapFeePercentage(
        address pool,
        uint256 newProtocolSwapFeePercentage
    ) external withValidSwapFee(newProtocolSwapFeePercentage) withLatestFees(pool) authenticate {
        (, uint256 poolCreatorFeePercentage) = getVault().getPoolCreatorInfo(pool);

        // Update local storage of the raw percentage
        _poolProtocolSwapFeePercentages[pool] = newProtocolSwapFeePercentage;
        // Update the resulting aggregate swap fee value in the Vault (PoolConfig).
        getVault().updateAggregateSwapFeePercentage(
            pool,
            _getAggregateFeePercentage(newProtocolSwapFeePercentage, poolCreatorFeePercentage)
        );

        emit ProtocolSwapFeePercentageChanged(pool, newProtocolSwapFeePercentage);
    }

    /// @inheritdoc IProtocolFeeCollector
    function setProtocolYieldFeePercentage(
        address pool,
        uint256 newProtocolYieldFeePercentage
    ) external withValidYieldFee(newProtocolYieldFeePercentage) withLatestFees(pool) authenticate {
        (, uint256 poolCreatorFeePercentage) = getVault().getPoolCreatorInfo(pool);

        // Update local storage of the raw percentage
        _poolProtocolYieldFeePercentages[pool] = newProtocolYieldFeePercentage;
        // Update the resulting aggregate yield fee value in the Vault (PoolConfig).
        getVault().updateAggregateYieldFeePercentage(
            pool,
            _getAggregateFeePercentage(newProtocolYieldFeePercentage, poolCreatorFeePercentage)
        );

        emit ProtocolSwapFeePercentageChanged(pool, newProtocolYieldFeePercentage);
    }

    /// @inheritdoc IProtocolFeeCollector
    function withdrawProtocolFees(address pool, address recipient) external authenticate {
        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);

        for (uint256 i = 0; i < numTokens; ++i) {
            IERC20 token = poolTokens[i];

            uint256 amountToWithdraw = _totalProtocolFeesCollected[pool][token];
            if (amountToWithdraw > 0) {
                _totalProtocolFeesCollected[pool][token] = 0;
                token.safeTransfer(recipient, amountToWithdraw);
            }
        }
    }

    /// @inheritdoc IProtocolFeeCollector
    function withdrawPoolCreatorFees(address pool, address recipient) external onlyPoolCreator(pool) {
        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);

        for (uint256 i = 0; i < numTokens; ++i) {
            IERC20 token = poolTokens[i];

            uint256 amountToWithdraw = _totalPoolCreatorFeesCollected[pool][token];
            if (amountToWithdraw > 0) {
                _totalPoolCreatorFeesCollected[pool][token] = 0;
                token.safeTransfer(recipient, amountToWithdraw);
            }
        }
    }
}
