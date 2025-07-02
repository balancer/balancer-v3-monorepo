// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { ILBPMigrationRouter } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPMigrationRouter.sol";
import { ILBPool, LBPoolImmutableData } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import {
    TokenConfig,
    RemoveLiquidityParams,
    RemoveLiquidityKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import {
    BalancerContractRegistry,
    ContractType
} from "@balancer-labs/v3-standalone-utils/contracts/BalancerContractRegistry.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";

import { WeightedPoolFactory } from "../WeightedPoolFactory.sol";
import { BPTTimeLocker } from "./BPTTimeLocker.sol";
import { LBPool } from "./LBPool.sol";

contract LBPMigrationRouter is ILBPMigrationRouter, ReentrancyGuardTransient, Version, VaultGuard, BPTTimeLocker {
    using FixedPoint for uint256;
    using SafeCast for uint256;

    // LBPs are constrained to two tokens: project and reserve.
    uint256 private constant _TWO_TOKENS = 2;
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

    constructor(
        BalancerContractRegistry contractRegistry,
        string memory version
    ) Version(version) VaultGuard(contractRegistry.getVault()) {
        (address weightedPoolFactoryAddress, bool isActive) = contractRegistry.getBalancerContract(
            ContractType.POOL_FACTORY,
            "WeightedPool"
        );
        if (isActive == false) {
            revert NoRegisteredWeightedPoolFactory();
        }

        _weightedPoolFactory = WeightedPoolFactory(weightedPoolFactoryAddress);
    }

    /// @inheritdoc ILBPMigrationRouter
    function migrateLiquidity(
        ILBPool lbp,
        address excessReceiver,
        WeightedPoolParams memory params
    ) external onlyLBPOwner(lbp) nonReentrant returns (IWeightedPool, uint256[] memory, uint256) {
        return _migrateLiquidity(lbp, msg.sender, excessReceiver, params, false);
    }

    /// @inheritdoc ILBPMigrationRouter
    function queryMigrateLiquidity(
        ILBPool lbp,
        address sender,
        address excessReceiver,
        WeightedPoolParams memory params
    ) external returns (uint256[] memory exactAmountsIn, uint256 bptAmountOut) {
        (, exactAmountsIn, bptAmountOut) = _migrateLiquidity(lbp, sender, excessReceiver, params, true);
    }

    function migrateLiquidityHook(
        MigrationHookParams memory params
    ) external onlyVault returns (uint256[] memory exactAmountsIn, uint256 bptAmountOut) {
        (, uint256[] memory removeAmountsOut, ) = _vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: address(params.lbp),
                from: params.sender,
                maxBptAmountIn: IERC20(address(params.lbp)).balanceOf(params.sender),
                minAmountsOut: new uint256[](_TWO_TOKENS),
                kind: RemoveLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );

        exactAmountsIn = _computeExactAmountsIn(
            params.lbp,
            params.bptPercentageToMigrate,
            params.migrationWeightProjectToken,
            params.migrationWeightReserveToken,
            removeAmountsOut
        );

        for (uint256 i = 0; i < _TWO_TOKENS; i++) {
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
        _lockBPT(IERC20(address(params.weightedPool)), params.sender, bptAmountOut, params.bptLockDuration);

        emit PoolMigrated(params.lbp, params.weightedPool, exactAmountsIn, bptAmountOut);
    }

    function _migrateLiquidity(
        ILBPool lbp,
        address sender,
        address excessReceiver,
        WeightedPoolParams memory params,
        bool isQuery
    ) internal returns (IWeightedPool weightedPool, uint256[] memory exactAmountsIn, uint256 bptAmountOut) {
        LBPoolImmutableData memory lbpImmutableData = lbp.getLBPoolImmutableData();

        if (lbpImmutableData.migrationRouter != address(this)) {
            revert IncorrectMigrationRouter(lbpImmutableData.migrationRouter, address(this));
        }

        // WeightedPool ensures the weights sum up to FP(1), reverting otherwise
        uint256[] memory normalizedWeights = new uint256[](_TWO_TOKENS);
        normalizedWeights[lbpImmutableData.projectTokenIndex] = lbpImmutableData.migrationWeightProjectToken;
        normalizedWeights[lbpImmutableData.reserveTokenIndex] = lbpImmutableData.migrationWeightReserveToken;

        TokenConfig[] memory tokensConfig = new TokenConfig[](_TWO_TOKENS);
        for (uint256 i = 0; i < _TWO_TOKENS; i++) {
            tokensConfig[i].token = lbpImmutableData.tokens[i];
        }

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

        MigrationHookParams memory migrateHookParams = MigrationHookParams({
            lbp: lbp,
            weightedPool: weightedPool,
            tokens: lbpImmutableData.tokens,
            sender: sender,
            excessReceiver: excessReceiver,
            bptLockDuration: lbpImmutableData.bptLockDuration,
            bptPercentageToMigrate: lbpImmutableData.bptPercentageToMigrate,
            migrationWeightProjectToken: lbpImmutableData.migrationWeightProjectToken,
            migrationWeightReserveToken: lbpImmutableData.migrationWeightReserveToken
        });

        if (isQuery) {
            (exactAmountsIn, bptAmountOut) = abi.decode(
                _vault.quote(abi.encodeCall(LBPMigrationRouter.migrateLiquidityHook, migrateHookParams)),
                (uint256[], uint256)
            );
        } else {
            (exactAmountsIn, bptAmountOut) = abi.decode(
                _vault.unlock(abi.encodeCall(LBPMigrationRouter.migrateLiquidityHook, migrateHookParams)),
                (uint256[], uint256)
            );
        }
    }

    function _computeExactAmountsIn(
        ILBPool lbp,
        uint256 bptPercentageToMigrate,
        uint256 migrationWeightProjectToken,
        uint256 migrationWeightReserveToken,
        uint256[] memory removeAmountsOut
    ) internal view returns (uint256[] memory exactAmountsIn) {
        exactAmountsIn = new uint256[](_TWO_TOKENS);

        uint256[] memory currentWeights = lbp.getLBPoolDynamicData().normalizedWeights;
        LBPoolImmutableData memory data = lbp.getLBPoolImmutableData();

        // Compute the spot price (reserve tokens per project token) based on the current weights and the amounts out
        // from the LBP.
        uint256 price = (removeAmountsOut[data.projectTokenIndex] * currentWeights[data.reserveTokenIndex]).divDown(
            removeAmountsOut[data.reserveTokenIndex] * currentWeights[data.projectTokenIndex]
        );

        // Calculate the reserve amount for the weighted pool based on the LBP ending price and the new weights.
        // We start by assuming we can withdraw the entire project token balance. We want to use as much as possible,
        // as the purpose of the weighted pool is to provide post-sale liquidity for the project token.
        //
        // If this isn't possible, since using the full project balance would require more reserve tokens than we have
        // available, we fall back on using the full reserve balance and calculating the project amount instead.
        uint256 reserveAmountOut = (removeAmountsOut[data.projectTokenIndex] * migrationWeightReserveToken).divDown(
            price * migrationWeightProjectToken
        );
        uint256 projectAmountOut;

        // If the reserveAmountOut is greater than the amount of reserve tokens removed, we need to calculate
        // projectAmountOut based on the price and the new weights.
        if (reserveAmountOut > removeAmountsOut[data.reserveTokenIndex]) {
            reserveAmountOut = removeAmountsOut[data.reserveTokenIndex];
            projectAmountOut = price.mulDown(reserveAmountOut).mulDown(migrationWeightProjectToken).divDown(
                migrationWeightReserveToken
            );
        } else {
            projectAmountOut = removeAmountsOut[data.projectTokenIndex];
        }

        // Calculate the exact amounts in based on the share to migrate.
        exactAmountsIn[data.projectTokenIndex] = projectAmountOut.mulDown(bptPercentageToMigrate);
        exactAmountsIn[data.reserveTokenIndex] = reserveAmountOut.mulDown(bptPercentageToMigrate);
    }
}
