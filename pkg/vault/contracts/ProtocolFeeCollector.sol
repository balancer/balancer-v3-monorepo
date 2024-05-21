// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    IProtocolFeeCollector, ProtocolFeeType
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

    // Maximum aggregate protocol swap fee percentage. 1e18 corresponds to a 100% fee.
    uint256 internal constant _MAX_AGGREGATE_SWAP_FEE_PERCENTAGE = 50e16; // 50%

    // Maximum aggregate protocol yield fee percentage.
    uint256 internal constant _MAX_AGGREGATE_YIELD_FEE_PERCENTAGE = 20e16; // 20%

    // Global protocol swap fee.
    uint256 private _aggregateSwapFeePercentage;

    // Global protocol yield fee.
    uint256 private _aggregateYieldFeePercentage;

    // Pool -> (Token -> fee): aggregate protocol swap and yield fees sent from the Vault.
    mapping(address => mapping(IERC20 => uint256)) internal _protocolFeesCollected;

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
        _disaggregateFees(pool);
        _;
    }

    // Ensure that the caller is the pool creator.
    modifier fromPoolCreator(address pool) {
        _ensureCallerIsPoolCreator(pool);
        _;
    }

    modifier withValidSwapFee(uint256 newSwapFeePercentage) {
        if (newSwapFeePercentage > _MAX_AGGREGATE_SWAP_FEE_PERCENTAGE) {
            revert AggregateSwapFeePercentageTooHigh();
        }
        _;
    }

    modifier withValidYieldFee(uint256 newYieldFeePercentage) {
        if (newYieldFeePercentage > _MAX_AGGREGATE_YIELD_FEE_PERCENTAGE) {
            revert AggregateYieldFeePercentageTooHigh();
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
    function getGlobalAggregateSwapFeePercentage() public view returns (uint256) {
        return _aggregateSwapFeePercentage;
    }

    /// @inheritdoc IProtocolFeeCollector
    function getGlobalAggregateYieldFeePercentage() public view returns (uint256) {
        return _aggregateYieldFeePercentage;
    }

    /// @inheritdoc IProtocolFeeCollector
    function setGlobalAggregateSwapFeePercentage(
        uint256 newAggregateSwapFeePercentage
    ) external authenticate withValidSwapFee(newAggregateSwapFeePercentage) {
        _aggregateSwapFeePercentage = newAggregateSwapFeePercentage;

        emit GlobalAggregateSwapFeePercentageChanged(newAggregateSwapFeePercentage);
    }

    /// @inheritdoc IProtocolFeeCollector
    function setGlobalAggregateYieldFeePercentage(
        uint256 newAggregateYieldFeePercentage
    ) external authenticate withValidYieldFee(newAggregateYieldFeePercentage) {
        _aggregateYieldFeePercentage = newAggregateYieldFeePercentage;

        emit GlobalAggregateYieldFeePercentageChanged(newAggregateYieldFeePercentage);
    }

    /// @inheritdoc IProtocolFeeCollector
    function setAggregateSwapFeePercentage(
        address pool,
        uint256 newAggregateSwapFeePercentage
    ) external authenticate withValidSwapFee(newAggregateSwapFeePercentage) withLatestFees(pool) {
        // Update the aggregate swap fee value in the Vault (PoolConfig).
        getVault().updateAggregateFeePercentage(
            pool,
            ProtocolFeeType.SWAP,
            newAggregateSwapFeePercentage
        );

        emit AggregateSwapFeePercentageChanged(pool, newAggregateSwapFeePercentage);
    }

    /// @inheritdoc IProtocolFeeCollector
    function setAggregateYieldFeePercentage(
        address pool,
        uint256 newAggregateYieldFeePercentage
    ) external authenticate withValidYieldFee(newAggregateYieldFeePercentage) withLatestFees(pool) {
        // Update the aggregate yield fee value in the Vault (PoolConfig).
        getVault().updateAggregateFeePercentage(
            pool,
            ProtocolFeeType.YIELD,
            newAggregateYieldFeePercentage
        );

        emit AggregateSwapFeePercentageChanged(pool, newAggregateYieldFeePercentage);
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
    function _disaggregateFees(address pool) private {
        (address poolCreator, uint256 poolCreatorFeeRatio) = getVault().getPoolCreatorInfo(pool);

        bool needToSplitWithPoolCreator = poolCreator != address(0) && poolCreatorFeeRatio > 0;

        IERC20[] memory poolTokens = getVault().getPoolTokens(pool);
        for (uint256 i = 0; i < poolTokens.length; ++i) {
            IERC20 token = poolTokens[i];
            uint256 totalFees = _protocolFeesCollected[pool][token];
            // Zero out collected fees prior to distribution.
            _protocolFeesCollected[pool][token] = 0;

            uint256 poolCreatorPortion;
            uint256 protocolPortion;

            if (needToSplitWithPoolCreator) {
                poolCreatorPortion = totalFees.mulDown(poolCreatorFeeRatio);
                protocolPortion = totalFees - protocolPortion;

                _poolCreatorFeesToWithdraw[pool][token] += poolCreatorPortion;
            } else {
                protocolPortion = totalFees;
            }

            _protocolFeesToWithdraw[pool][token] += protocolPortion;
        }
    }

    // Functions that must be called by the Vault

    /// @inheritdoc IProtocolFeeCollector
    function receiveProtocolFees(address pool, IERC20 token, uint256 amount) external onlyVault {
        _protocolFeesCollected[pool][token] += amount;

        token.safeTransferFrom(address(getVault()), address(this), amount);

        emit ProtocolFeeCollected(pool, token, amount);
    }
}
