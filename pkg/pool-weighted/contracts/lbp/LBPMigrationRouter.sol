// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { ILBPMigrationRouter } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPMigrationRouter.sol";
import { ILBPool, LBPoolImmutableData } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
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
import { BalancerContractRegistry } from "@balancer-labs/v3-standalone-utils/contracts/BalancerContractRegistry.sol";

import { WeightedPoolFactory } from "../WeightedPoolFactory.sol";

contract LBPMigrationRouter is ILBPMigrationRouter, Version, VaultGuard {
    using SafeERC20 for IERC20;

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
        uint256[] memory exactAmountsIn,
        uint256 minAddBptAmountOut,
        uint256[] memory minRemoveAmountsOut,
        address excessReceiver,
        WeightedPoolParams memory params
    ) external onlyLBPOwner(lbp) returns (IWeightedPool, uint256) {
        return
            _migrateLiquidity(
                lbp,
                exactAmountsIn,
                minAddBptAmountOut,
                minRemoveAmountsOut,
                msg.sender,
                excessReceiver,
                params,
                false
            );
    }

    /// @inheritdoc ILBPMigrationRouter
    function queryMigrateLiquidity(
        ILBPool lbp,
        uint256[] memory exactAmountsIn,
        address sender,
        address excessReceiver,
        WeightedPoolParams memory params
    ) external returns (uint256 bptAmountOut) {
        (, bptAmountOut) = _migrateLiquidity(
            lbp,
            exactAmountsIn,
            0,
            new uint256[](exactAmountsIn.length),
            sender,
            excessReceiver,
            params,
            true
        );
    }

    function migrateLiquidityHook(MigrationHookParams memory params) external onlyVault returns (uint256 bptAmountOut) {
        (, uint256[] memory removeAmountsOut, ) = _vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: address(params.lbp),
                from: params.sender,
                maxBptAmountIn: IERC20(address(params.lbp)).balanceOf(params.sender),
                minAmountsOut: params.minRemoveAmountsOut,
                kind: RemoveLiquidityKind.PROPORTIONAL,
                userData: new bytes(0)
            })
        );

        for (uint256 i = 0; i < removeAmountsOut.length; i++) {
            if (params.exactAmountsIn[i] > removeAmountsOut[i]) {
                revert InsufficientInputAmount(params.tokens[i], removeAmountsOut[i]);
            }

            uint256 remainingBalance = removeAmountsOut[i] - params.exactAmountsIn[i];
            if (remainingBalance > 0) {
                _vault.sendTo(params.tokens[i], params.excessReceiver, remainingBalance);
            }
        }

        bptAmountOut = _vault.initialize(
            address(params.weightedPool),
            params.sender,
            params.tokens,
            params.exactAmountsIn,
            params.minAddBptAmountOut,
            bytes("")
        );

        emit PoolMigrated(params.lbp, params.weightedPool, bptAmountOut);
    }

    function _migrateLiquidity(
        ILBPool lbp,
        uint256[] memory exactAmountsIn,
        uint256 minAddBptAmountOut,
        uint256[] memory minRemoveAmountsOut,
        address sender,
        address excessReceiver,
        WeightedPoolParams memory params,
        bool isQuery
    ) internal returns (IWeightedPool weightedPool, uint256 bptAmountOut) {
        LBPoolImmutableData memory lbpImmutableData = lbp.getLBPoolImmutableData();

        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp <= lbpImmutableData.endTime) {
            revert LBPWeightsNotFinalized(lbp);
        }

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
                _params.normalizedWeights,
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
        migrateHookParams.exactAmountsIn = exactAmountsIn;
        migrateHookParams.minAddBptAmountOut = minAddBptAmountOut;
        migrateHookParams.minRemoveAmountsOut = minRemoveAmountsOut;

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
}
