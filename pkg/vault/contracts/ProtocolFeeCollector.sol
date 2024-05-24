// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    IProtocolFeeCollector,
    ProtocolFeeType
} from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeCollector.sol";
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

    // Pool -> (Token -> fee): aggregate protocol swap fees sent from the Vault.
    mapping(address => mapping(IERC20 => uint256)) internal _protocolSwapFeesCollected;

    // Pool -> (Token -> fee): aggregate protocol yield fees sent from the Vault.
    mapping(address => mapping(IERC20 => uint256)) internal _protocolYieldFeesCollected;

    // Aggregate (= protocol + creator) fees are collected by the Vault on swap and yield, and accumulate in the
    // "Collected" fields. When queried or withdrawn, they are disaggregated and moved to the "ToWithdraw" storage,
    // where they can be withdrawn by the protocol or pool creator.

    // Pool -> (Token -> fee): Disaggregated protocol fees (from swap and yield), available for withdrawal
    // by governance.
    mapping(address => mapping(IERC20 => uint256)) internal _protocolFeesToWithdraw;

    // Pool -> (Token -> fee): Disaggregated pool creator fees (from swap and yield), available for withdrawal by
    // the pool creator.
    mapping(address => mapping(IERC20 => uint256)) internal _poolCreatorFeesToWithdraw;

    modifier onlyVault() {
        if (msg.sender != address(getVault())) {
            revert IVaultErrors.SenderIsNotVault(msg.sender);
        }
        _;
    }

    // Force collection and disaggregation, to ensure the values in "ToWithdraw" storage are correct.
    modifier withLatestFees(address pool) {
        getVault().collectProtocolFees(pool);
        _disaggregateFees(pool, ProtocolFeeType.SWAP);
        _disaggregateFees(pool, ProtocolFeeType.YIELD);
        _;
    }

    // Ensure that the caller is the pool creator.
    modifier fromPoolCreator(address pool) {
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
        getVault().updateAggregateFeePercentage(
            pool,
            ProtocolFeeType.SWAP,
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
        getVault().updateAggregateFeePercentage(
            pool,
            ProtocolFeeType.YIELD,
            _getAggregateFeePercentage(newProtocolYieldFeePercentage, poolCreatorFeePercentage)
        );

        emit ProtocolSwapFeePercentageChanged(pool, newProtocolYieldFeePercentage);
    }

    /// @inheritdoc IProtocolFeeCollector
    function getCollectedProtocolFeeAmounts(
        address pool
    ) public withLatestFees(pool) returns (uint256[] memory feeAmounts) {
        IERC20[] memory tokens = getVault().getPoolTokens(pool);
        uint256 numTokens = tokens.length;

        feeAmounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            feeAmounts[i] = _protocolFeesToWithdraw[pool][tokens[i]];
        }
    }

    /// @inheritdoc IProtocolFeeCollector
    function getCollectedPoolCreatorFeeAmounts(
        address pool
    ) public withLatestFees(pool) returns (uint256[] memory feeAmounts) {
        IERC20[] memory tokens = getVault().getPoolTokens(pool);
        uint256 numTokens = tokens.length;

        feeAmounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            feeAmounts[i] = _poolCreatorFeesToWithdraw[pool][tokens[i]];
        }
    }

    /// @inheritdoc IProtocolFeeCollector
    function withdrawProtocolFees(address pool, address recipient) external authenticate {
        // This call ensures all fees are collected and disaggregated.
        uint256[] memory feeAmounts = getCollectedProtocolFeeAmounts(pool);
        IERC20[] memory tokens = getVault().getPoolTokens(pool);

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];

            uint256 amountToWithdraw = feeAmounts[i];
            if (amountToWithdraw > 0) {
                _protocolFeesToWithdraw[pool][token] = 0;
                token.safeTransfer(recipient, amountToWithdraw);
            }
        }
    }

    /// @inheritdoc IProtocolFeeCollector
    function withdrawPoolCreatorFees(address pool, address recipient) external fromPoolCreator(pool) {
        // This call ensures all fees are collected and disaggregated.
        uint256[] memory feeAmounts = getCollectedPoolCreatorFeeAmounts(pool);
        IERC20[] memory tokens = getVault().getPoolTokens(pool);

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];

            uint256 amountToWithdraw = feeAmounts[i];
            if (amountToWithdraw > 0) {
                _poolCreatorFeesToWithdraw[pool][token] = 0;
                token.safeTransfer(recipient, amountToWithdraw);
            }
        }
    }

    /// @inheritdoc IProtocolFeeCollector
    function getAggregateFeePercentage(
        ProtocolFeeType feeType,
        uint256 poolCreatorFeePercentage
    ) public view returns (uint256) {
        // Get default global protocol fee percentages.
        uint256 protocolFeePercentage = feeType == ProtocolFeeType.SWAP
            ? _protocolSwapFeePercentage
            : _protocolYieldFeePercentage;

        return _getAggregateFeePercentage(protocolFeePercentage, poolCreatorFeePercentage);
    }

    function _getAggregateFeePercentage(
        uint256 protocolFeePercentage,
        uint256 poolCreatorFeePercentage
    ) private pure returns (uint256) {
        return protocolFeePercentage + protocolFeePercentage.complement().mulDown(poolCreatorFeePercentage);
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

    // Disaggregate and move balances from <Fees>Collected to <Fees>ToWithdraw
    function _disaggregateFees(address pool, ProtocolFeeType feeType) private {
        (address poolCreator, uint256 poolCreatorFeePercentage) = getVault().getPoolCreatorInfo(pool);

        bool needToSplitWithPoolCreator = poolCreator != address(0) && poolCreatorFeePercentage > 0;
        uint256 aggregateFeePercentage;
        uint256 protocolFeePercentage;

        if (needToSplitWithPoolCreator) {
            protocolFeePercentage = feeType == ProtocolFeeType.SWAP
                ? _poolProtocolSwapFeePercentages[pool]
                : _poolProtocolYieldFeePercentages[pool];

            // Only need this if there is a pool creator and fees must be split
            aggregateFeePercentage = _getAggregateFeePercentage(protocolFeePercentage, poolCreatorFeePercentage);
        }

        IERC20[] memory poolTokens = getVault().getPoolTokens(pool);
        for (uint256 i = 0; i < poolTokens.length; ++i) {
            IERC20 token = poolTokens[i];
            uint256 poolCreatorPortion;
            uint256 protocolPortion;

            uint256 totalFees = feeType == ProtocolFeeType.SWAP
                ? _protocolSwapFeesCollected[pool][token]
                : _protocolYieldFeesCollected[pool][token];

            if (needToSplitWithPoolCreator) {
                uint256 totalVolume = totalFees.divUp(aggregateFeePercentage);
                protocolPortion = totalVolume.mulUp(protocolFeePercentage);
                poolCreatorPortion = totalFees - protocolPortion;
            } else {
                protocolPortion = totalFees;
            }

            if (feeType == ProtocolFeeType.SWAP) {
                _protocolSwapFeesCollected[pool][token] = 0;

                _protocolFeesToWithdraw[pool][token] += protocolPortion;
                _poolCreatorFeesToWithdraw[pool][token] += poolCreatorPortion;
            } else {
                _protocolYieldFeesCollected[pool][token] = 0;

                _protocolFeesToWithdraw[pool][token] += protocolPortion;
                _poolCreatorFeesToWithdraw[pool][token] += poolCreatorPortion;
            }
        }
    }

    // Functions that must be called by the Vault

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

    /// @inheritdoc IProtocolFeeCollector
    function receiveProtocolSwapFees(address pool, IERC20 token, uint256 amount) external onlyVault {
        _protocolSwapFeesCollected[pool][token] += amount;

        token.safeTransferFrom(address(getVault()), address(this), amount);

        emit ProtocolSwapFeeCollected(pool, token, amount);
    }

    /// @inheritdoc IProtocolFeeCollector
    function receiveProtocolYieldFees(address pool, IERC20 token, uint256 amount) external onlyVault {
        _protocolYieldFeesCollected[pool][token] += amount;

        token.safeTransferFrom(address(getVault()), address(this), amount);

        emit ProtocolYieldFeeCollected(pool, token, amount);
    }
}
