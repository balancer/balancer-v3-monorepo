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
import { PoolFeeConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

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

    struct PoolFees {
        uint256 protocolSwapFeePercentage;
        uint256 protocolYieldFeePercentage;
        uint256 poolCreatorFeePercentage;
    }

    // Maximum protocol swap fee percentage. 1e18 corresponds to a 100% fee.
    uint256 internal constant _MAX_PROTOCOL_SWAP_FEE_PERCENTAGE = 50e16; // 50%

    // Maximum protocol yield fee percentage.
    uint256 internal constant _MAX_PROTOCOL_YIELD_FEE_PERCENTAGE = 20e16; // 20%

    // Global protocol swap fee.
    uint256 private _protocolSwapFeePercentage;

    // Global protocol yield fee.
    uint256 private _protocolYieldFeePercentage;

    // Pool -> Pool creator.
    mapping(address => address) private _poolCreators;

    // Swap and Yield fees cannot be combined, since the pool creator split can be different for each.

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

    // Pool -> PoolFees): Pool-specific fee percentages, as registered (or subsequently updated).
    mapping(address => PoolFees) internal _poolFeePercentages;

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
    function getGlobalProtocolSwapFeePercentage() public view returns (uint256) {
        return _protocolSwapFeePercentage;
    }

    /// @inheritdoc IProtocolFeeCollector
    function getGlobalProtocolYieldFeePercentage() public view returns (uint256) {
        return _protocolYieldFeePercentage;
    }

    /// @inheritdoc IProtocolFeeCollector
    function getPoolCreator(address pool) public view returns (address) {
        return _poolCreators[pool];
    }

    /// @inheritdoc IProtocolFeeCollector
    function setGlobalProtocolSwapFeePercentage(
        uint256 newProtocolSwapFeePercentage
    ) external authenticate withValidSwapFee(newProtocolSwapFeePercentage) {
        _protocolSwapFeePercentage = newProtocolSwapFeePercentage;

        emit GlobalProtocolSwapFeePercentageChanged(newProtocolSwapFeePercentage);
    }

    /// @inheritdoc IProtocolFeeCollector
    function setGlobalProtocolYieldFeePercentage(
        uint256 newProtocolYieldFeePercentage
    ) external authenticate withValidYieldFee(newProtocolYieldFeePercentage) {
        _protocolYieldFeePercentage = newProtocolYieldFeePercentage;

        emit GlobalProtocolSwapFeePercentageChanged(newProtocolYieldFeePercentage);
    }

    /// @inheritdoc IProtocolFeeCollector
    function setProtocolSwapFeePercentage(
        address pool,
        uint256 newProtocolSwapFeePercentage
    ) external authenticate withValidSwapFee(newProtocolSwapFeePercentage) withLatestFees(pool) {
        // Update the swap fee in local storage.
        _poolFeePercentages[pool].protocolSwapFeePercentage = newProtocolSwapFeePercentage;
        // Update the aggregate swap fee value in the Vault (PoolConfig).
        getVault().updateAggregateFeePercentage(
            pool,
            ProtocolFeeType.SWAP,
            _getAggregateFeePercentage(newProtocolSwapFeePercentage, _poolFeePercentages[pool].poolCreatorFeePercentage)
        );

        emit ProtocolSwapFeePercentageChanged(pool, newProtocolSwapFeePercentage);
    }

    /// @inheritdoc IProtocolFeeCollector
    function setProtocolYieldFeePercentage(
        address pool,
        uint256 newProtocolYieldFeePercentage
    ) external authenticate withValidYieldFee(newProtocolYieldFeePercentage) withLatestFees(pool) {
        // Update the yield fee in local storage.
        _poolFeePercentages[pool].protocolYieldFeePercentage = newProtocolYieldFeePercentage;
        // Update the aggregate yield fee value in the Vault (PoolConfig).
        getVault().updateAggregateFeePercentage(
            pool,
            ProtocolFeeType.YIELD,
            _getAggregateFeePercentage(
                newProtocolYieldFeePercentage,
                _poolFeePercentages[pool].poolCreatorFeePercentage
            )
        );

        emit ProtocolSwapFeePercentageChanged(pool, newProtocolYieldFeePercentage);
    }

    function setPoolCreatorFeePercentage(
        address pool,
        uint256 newPoolCreatorFeePercentage
    ) external fromPoolCreator(pool) withLatestFees(pool) {
        if (newPoolCreatorFeePercentage > FixedPoint.ONE) {
            revert PoolCreatorFeePercentageTooHigh();
        }

        // Update the fee local storage.
        _poolFeePercentages[pool].poolCreatorFeePercentage = newPoolCreatorFeePercentage;

        PoolFees memory poolFees = _poolFeePercentages[pool];

        // Update the aggregate swap and yield fee values in the Vault (PoolConfig).
        getVault().updateAggregateFeePercentage(
            pool,
            ProtocolFeeType.SWAP,
            _getAggregateFeePercentage(poolFees.protocolSwapFeePercentage, newPoolCreatorFeePercentage)
        );
        getVault().updateAggregateFeePercentage(
            pool,
            ProtocolFeeType.YIELD,
            _getAggregateFeePercentage(poolFees.protocolYieldFeePercentage, newPoolCreatorFeePercentage)
        );

        emit PoolCreatorFeePercentageChanged(pool, newPoolCreatorFeePercentage);
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
        address poolCreator = getPoolCreator(pool);

        if (poolCreator == address(0)) {
            revert PoolCreatorNotRegistered(pool);
        }

        if (poolCreator != msg.sender) {
            revert CallerIsNotPoolCreator(msg.sender);
        }
    }

    // Disaggregate and move balances from <Fees>Collected to <Fees>ToWithdraw
    function _disaggregateFees(address pool, ProtocolFeeType feeType) private {
        PoolFees memory poolFees = _poolFeePercentages[pool];
        uint256 protocolFeePercentage = feeType == ProtocolFeeType.SWAP
            ? poolFees.protocolSwapFeePercentage
            : poolFees.protocolYieldFeePercentage;

        bool needToSplitWithPoolCreator = getPoolCreator(pool) != address(0) && poolFees.poolCreatorFeePercentage > 0;
        uint256 aggregateFeePercentage;

        if (needToSplitWithPoolCreator) {
            // Only need this if there is a pool creator and fees must be split
            aggregateFeePercentage = _getAggregateFeePercentage(
                protocolFeePercentage,
                poolFees.poolCreatorFeePercentage
            );
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
    function registerPoolFeeConfig(
        address pool,
        PoolFeeConfig calldata feeConfig
    )
        public
        onlyVault
        withValidSwapFee(feeConfig.protocolSwapFeePercentage)
        returns (uint256 aggregateSwapFeePercentage, uint256 aggregateYieldFeePercentage)
    {
        if (feeConfig.poolCreator == address(0)) {
            // Cannot have a pool creator fee if there is no pool creator.
            if (feeConfig.poolCreatorFeePercentage > 0) {
                revert InvalidFeeConfiguration();
            }
        } else {
            // Ensure any custom pool creator fee is within the valid range
            if (feeConfig.poolCreatorFeePercentage > FixedPoint.ONE) {
                revert PoolCreatorFeePercentageTooHigh();
            }

            _poolCreators[pool] = feeConfig.poolCreator;
        }

        // We don't support arbitrary yield fees. Use the global percentage; projects can exempt individual tokens
        // using the `paysYieldFees` flag in TokenConfig.
        uint256 protocolYieldFeePercentage = getGlobalProtocolYieldFeePercentage();

        _poolFeePercentages[pool] = PoolFees({
            protocolSwapFeePercentage: feeConfig.protocolSwapFeePercentage,
            protocolYieldFeePercentage: protocolYieldFeePercentage,
            poolCreatorFeePercentage: feeConfig.poolCreatorFeePercentage
        });

        // Compute aggregate fee return values.
        aggregateSwapFeePercentage = _getAggregateFeePercentage(
            feeConfig.protocolSwapFeePercentage,
            feeConfig.poolCreatorFeePercentage
        );
        aggregateYieldFeePercentage = _getAggregateFeePercentage(
            protocolYieldFeePercentage,
            feeConfig.poolCreatorFeePercentage
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
