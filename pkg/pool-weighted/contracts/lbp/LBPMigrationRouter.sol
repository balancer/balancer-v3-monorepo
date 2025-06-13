// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/console.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { ILBPMigrationRouter } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPMigrationRouter.sol";
import {
    ILBPool,
    LBPoolImmutableData,
    LBPParams
} from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { ContractType } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IBalancerContractRegistry.sol";
import {
    PoolRoleAccounts,
    TokenConfig,
    TokenType,
    RemoveLiquidityParams,
    RemoveLiquidityKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BalancerContractRegistry } from "@balancer-labs/v3-standalone-utils/contracts/BalancerContractRegistry.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

import { WeightedPoolFactory } from "../WeightedPoolFactory.sol";

contract LBPMigrationRouter is ILBPMigrationRouter, ReentrancyGuardTransient, Version, VaultGuard {
    using FixedPoint for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    // LBPs are constrained to two tokens: project and reserve.
    uint256 private constant _TWO_TOKENS = 2;
    WeightedPoolFactory internal immutable _weightedPoolFactory;

    mapping(ILBPool => MigrationParams) private _migrationParams;
    mapping(address => TimeLockedAmount[]) private _timeLockedAmounts;

    modifier onlyLBPOwner(ILBPool lbp) {
        {
            address lbpOwner = Ownable(address(lbp)).owner();
            if (msg.sender != lbpOwner) {
                revert SenderIsNotLBPOwner();
            }
        }

        _;
    }

    constructor(
        BalancerContractRegistry contractRegistry,
        string memory version
    ) Version(version) VaultGuard(contractRegistry.getVault()) {
        (address weightedPoolFactoryAddress, bool isWeightedPoolFactoryActive) = contractRegistry.getBalancerContract(
            ContractType.POOL_FACTORY,
            "WeightedPool"
        );
        if (!isWeightedPoolFactoryActive) {
            revert ContractIsNotActiveInRegistry("WeightedPool");
        }

        _weightedPoolFactory = WeightedPoolFactory(weightedPoolFactoryAddress);
    }

    function getTimeLockedAmount(address sender, uint256 index) external view returns (TimeLockedAmount memory) {
        return _timeLockedAmounts[sender][index];
    }

    function getTimeLockedAmountsCount(address sender) external view returns (uint256) {
        return _timeLockedAmounts[sender].length;
    }

    function unlockTokens(uint256[] memory timeLockedIndexes) external {
        uint256 length = timeLockedIndexes.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 index = timeLockedIndexes[i];

            TimeLockedAmount memory timeLockedAmount = _timeLockedAmounts[msg.sender][index];
            console.log(timeLockedAmount.amount);
            if (timeLockedAmount.amount == 0) {
                revert NoTimeLockedAmount(index);
            }

            if (timeLockedAmount.unlockTimestamp > block.timestamp) {
                revert TimeLockedAmountNotUnlockedYet(index, timeLockedAmount.unlockTimestamp);
            }

            delete _timeLockedAmounts[msg.sender][index];

            IERC20(timeLockedAmount.token).safeTransfer(msg.sender, timeLockedAmount.amount);
        }
    }

    /// @inheritdoc ILBPMigrationRouter
    function setupMigration(
        ILBPool lbp,
        uint256 bptLockDuration,
        uint256 shareToMigrate,
        uint256 weight0,
        uint256 weight1
    ) external onlyLBPOwner(lbp) {
        if (_migrationParams[lbp].weight0 != 0) {
            revert MigrationAlreadySetup();
        }

        if (_vault.isPoolRegistered(address(lbp)) == false) {
            revert PoolNotRegistered();
        }

        LBPoolImmutableData memory lbpImmutableData = lbp.getLBPoolImmutableData();
        if (block.timestamp >= lbpImmutableData.startTime) {
            revert LBPAlreadyStarted(lbpImmutableData.startTime);
        }

        uint64 weight0Uint64 = weight0.toUint64();
        uint64 weight1Uint64 = weight1.toUint64();

        if (weight0Uint64 == 0 || weight1Uint64 == 0 || weight0Uint64 + weight1Uint64 != FixedPoint.ONE) {
            revert InvalidMigrationWeights();
        }

        _migrationParams[lbp] = MigrationParams({
            bptLockDuration: bptLockDuration.toUint64(),
            shareToMigrate: shareToMigrate.toUint64(),
            weight0: weight0Uint64,
            weight1: weight1Uint64
        });
    }

    /// @inheritdoc ILBPMigrationRouter
    function getMigrationParams(ILBPool lbp) external view returns (MigrationParams memory) {
        return _migrationParams[lbp];
    }

    /// @inheritdoc ILBPMigrationRouter
    function isMigrationSetup(ILBPool lbp) external view returns (bool) {
        return _migrationParams[lbp].weight0 != 0;
    }

    /// @inheritdoc ILBPMigrationRouter
    function migrateLiquidity(
        ILBPool lbp,
        uint256 minAddBptAmountOut,
        address excessReceiver,
        WeightedPoolParams memory params
    ) external onlyLBPOwner(lbp) returns (IWeightedPool, uint256) {
        return _migrateLiquidity(lbp, minAddBptAmountOut, msg.sender, excessReceiver, params, false);
    }

    /// @inheritdoc ILBPMigrationRouter
    function queryMigrateLiquidity(
        ILBPool lbp,
        address sender,
        address excessReceiver,
        WeightedPoolParams memory params
    ) external returns (uint256 bptAmountOut) {
        (, bptAmountOut) = _migrateLiquidity(lbp, 0, sender, excessReceiver, params, true);
    }

    function migrateLiquidityHook(MigrationHookParams memory params) external onlyVault returns (uint256 bptAmountOut) {
        (, uint256[] memory removeAmountsOut, ) = _vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: address(params.lbp),
                from: params.sender,
                maxBptAmountIn: IERC20(address(params.lbp)).balanceOf(params.sender),
                minAmountsOut: new uint256[](_TWO_TOKENS),
                kind: RemoveLiquidityKind.PROPORTIONAL,
                userData: new bytes(0)
            })
        );

        uint256[] memory exactAmountsIn = _computeExactAmountsIn(params, removeAmountsOut);

        for (uint256 i = 0; i < removeAmountsOut.length; i++) {
            uint256 remainingBalance = removeAmountsOut[i] - exactAmountsIn[i];
            if (remainingBalance > 0) {
                _vault.sendTo(params.tokens[i], params.excessReceiver, remainingBalance);
            }
        }

        bptAmountOut = _vault.initialize(
            address(params.weightedPool),
            address(this),
            params.tokens,
            exactAmountsIn,
            params.minAddBptAmountOut,
            bytes("")
        );

        _lockAmount(params, bptAmountOut);

        emit PoolMigrated(params.lbp, params.weightedPool, bptAmountOut);
    }

    function _migrateLiquidity(
        ILBPool lbp,
        uint256 minAddBptAmountOut,
        address sender,
        address excessReceiver,
        WeightedPoolParams memory params,
        bool isQuery
    ) internal returns (IWeightedPool weightedPool, uint256 bptAmountOut) {
        LBPoolImmutableData memory lbpImmutableData = lbp.getLBPoolImmutableData();

        MigrationParams memory migrationParams = _migrationParams[lbp];
        if (migrationParams.weight0 == 0) {
            revert MigrationDoesNotExist();
        }

        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp <= lbpImmutableData.endTime) {
            revert LBPWeightsNotFinalized(lbp);
        }

        uint256[] memory normalizedWeights = new uint256[](_TWO_TOKENS);
        normalizedWeights[0] = migrationParams.weight0;
        normalizedWeights[1] = migrationParams.weight1;

        TokenConfig[] memory tokensConfig = new TokenConfig[](lbpImmutableData.tokens.length);
        for (uint256 i = 0; i < lbpImmutableData.tokens.length; i++) {
            tokensConfig[i].token = lbpImmutableData.tokens[i];
        }

        // Stack too deep issue workaround
        WeightedPoolParams memory _params = params;
        weightedPool = IWeightedPool(
            _weightedPoolFactory.create(
                _params.name,
                _params.symbol,
                tokensConfig,
                normalizedWeights,
                _params.roleAccounts,
                _params.swapFeePercentage,
                _params.poolHooksContract,
                _params.enableDonation,
                _params.disableUnbalancedLiquidity,
                _params.salt
            )
        );

        MigrationHookParams memory migrateHookParams;
        // via-IR Stack too deep issue workaround
        migrateHookParams.lbp = lbp;
        migrateHookParams.weightedPool = weightedPool;
        migrateHookParams.tokens = lbpImmutableData.tokens;
        migrateHookParams.sender = sender;
        migrateHookParams.excessReceiver = excessReceiver;
        migrateHookParams.minAddBptAmountOut = minAddBptAmountOut;
        migrateHookParams.migrationParams = migrationParams;

        if (isQuery) {
            bptAmountOut = abi.decode(
                _vault.quote(abi.encodeCall(LBPMigrationRouter.migrateLiquidityHook, migrateHookParams)),
                (uint256)
            );
        } else {
            bptAmountOut = abi.decode(
                _vault.unlock(abi.encodeCall(LBPMigrationRouter.migrateLiquidityHook, migrateHookParams)),
                (uint256)
            );
        }
    }

    function _computeExactAmountsIn(
        MigrationHookParams memory params,
        uint256[] memory removeAmountsOut
    ) internal view returns (uint256[] memory exactAmountsIn) {
        exactAmountsIn = new uint256[](_TWO_TOKENS);

        uint256[] memory currentWeights = params.lbp.getLBPoolDynamicData().normalizedWeights;

        uint256 price = (removeAmountsOut[0] * currentWeights[1]).divDown(removeAmountsOut[1] * currentWeights[0]);

        uint256 b1 = (removeAmountsOut[0] * params.migrationParams.weight1).divDown(
            price * params.migrationParams.weight0
        );
        uint256 b0 = removeAmountsOut[0];

        if (b1 > removeAmountsOut[1]) {
            b1 = removeAmountsOut[1];
            b0 = price.mulDown(b1).mulDown(params.migrationParams.weight0).divDown(params.migrationParams.weight1);
        }

        uint256 shareToMigrate = params.migrationParams.shareToMigrate;
        exactAmountsIn[0] = b0.mulDown(shareToMigrate);
        exactAmountsIn[1] = b1.mulDown(shareToMigrate);
    }

    function _lockAmount(MigrationHookParams memory params, uint256 bptAmountOut) internal {
        uint256 unlockTimestamp = block.timestamp + params.migrationParams.bptLockDuration;

        _timeLockedAmounts[params.sender].push(
            TimeLockedAmount({
                token: address(params.weightedPool),
                amount: bptAmountOut,
                unlockTimestamp: unlockTimestamp
            })
        );

        emit AmountLocked(params.sender, address(params.weightedPool), bptAmountOut, unlockTimestamp);
    }
}
