// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { ILBPMigrationRouter } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPMigrationRouter.sol";
import { ILBPool, LBPoolImmutableData } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import {
    TokenConfig,
    RemoveLiquidityParams,
    RemoveLiquidityKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import {
    BalancerContractRegistry,
    ContractType
} from "@balancer-labs/v3-standalone-utils/contracts/BalancerContractRegistry.sol";

import { WeightedPoolFactory } from "../WeightedPoolFactory.sol";
import { Timelock } from "./Timelock.sol";

contract LBPMigrationRouter is ILBPMigrationRouter, Timelock, ReentrancyGuardTransient, Version, VaultGuard {
    using FixedPoint for uint256;
    using SafeCast for uint256;

    // LBPs are constrained to two tokens: project and reserve.
    uint256 private constant _TWO_TOKENS = 2;
    address internal immutable _trustedFactory;
    WeightedPoolFactory internal immutable _weightedPoolFactory;

    modifier onlyLBPOwner(ILBPool lbp) {
        {
            address lbpOwner = Ownable(address(lbp)).owner();
            if (msg.sender != lbpOwner) {
                revert SenderIsNotLBPOwner();
            }
        }

        _;
    }

    modifier onlyTrustedFactory() {
        if (msg.sender != _trustedFactory) {
            revert SenderIsNotTrustedFactory();
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

    /// @inheritdoc ILBPMigrationRouter
    function migrateLiquidity(
        ILBPool lbp,
        address excessReceiver,
        WeightedPoolParams memory params
    ) external onlyLBPOwner(lbp) nonReentrant returns (IWeightedPool, uint256) {
        return _migrateLiquidity(lbp, msg.sender, excessReceiver, params, false);
    }

    /// @inheritdoc ILBPMigrationRouter
    function queryMigrateLiquidity(
        ILBPool lbp,
        address sender,
        address excessReceiver,
        WeightedPoolParams memory params
    ) external returns (uint256 bptAmountOut) {
        (, bptAmountOut) = _migrateLiquidity(lbp, sender, excessReceiver, params, true);
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
            0,
            bytes("")
        );
        _lockAmount(
            IERC20(address(params.weightedPool)),
            params.sender,
            bptAmountOut,
            params.migrationParams.bptLockDuration
        );

        emit PoolMigrated(params.lbp, params.weightedPool, bptAmountOut);
    }

    function _migrateLiquidity(
        ILBPool lbp,
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

        // Compute the spot price based on the current weights and the amounts out from the LBP.
        uint256 price = (removeAmountsOut[0] * currentWeights[1]).divDown(removeAmountsOut[1] * currentWeights[0]);

        // Calculate balance1 based on the price and the new weights.
        // We start from the b0 balance because we treat it as the maximum.
        // If that's not the case, then b1 will end up being greater than amountOut0.
        uint256 b1 = (removeAmountsOut[0] * params.migrationParams.weight1).divDown(
            price * params.migrationParams.weight0
        );
        uint256 b0 = removeAmountsOut[0];

        // If b1 is greater than the amountOut1, we need to calculate b0 based on the price and the new weights.
        if (b1 > removeAmountsOut[1]) {
            b1 = removeAmountsOut[1];
            b0 = price.mulDown(b1).mulDown(params.migrationParams.weight0).divDown(params.migrationParams.weight1);
        }

        // Calculate the exact amounts in based on the share to migrate.
        uint256 shareToMigrate = params.migrationParams.shareToMigrate;
        exactAmountsIn[0] = b0.mulDown(shareToMigrate);
        exactAmountsIn[1] = b1.mulDown(shareToMigrate);
    }
}
