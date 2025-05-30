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
import {
    PoolRoleAccounts,
    TokenConfig,
    TokenType,
    RemoveLiquidityParams,
    RemoveLiquidityKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";

import { WeightedPoolFactory } from "./WeightedPoolFactory.sol";

contract LBPMigrationRouter is ILBPMigrationRouter, VaultGuard {
    using SafeERC20 for IERC20;

    IVault public immutable vault;
    address public immutable treasury;
    WeightedPoolFactory public immutable weightedPoolFactory;

    modifier onlyLBPOwner(ILBPool lbp) {
        {
            address lbpOwner = Ownable(address(lbp)).owner();
            if (msg.sender != lbpOwner) {
                revert SenderIsNotLBPOwner(lbpOwner);
            }
        }
        _;
    }

    constructor(IVault _vault, WeightedPoolFactory _weightedPoolFactory, address _treasury) VaultGuard(_vault) {
        vault = _vault;
        treasury = _treasury;
        weightedPoolFactory = _weightedPoolFactory;
    }

    /// @inheritdoc ILBPMigrationRouter
    function migrateLiquidity(
        ILBPool lbp,
        uint256[] memory exactAmountsIn,
        uint256 minAddBptAmountOut,
        uint256[] memory minRemoveAmountsOut,
        WeightedPoolParams memory params
    ) external onlyLBPOwner(lbp) returns (IWeightedPool, uint256) {
        return
            _migrateLiquidity(lbp, exactAmountsIn, minAddBptAmountOut, minRemoveAmountsOut, msg.sender, params, false);
    }

    /// @inheritdoc ILBPMigrationRouter
    function queryMigrateLiquidity(
        ILBPool lbp,
        uint256[] memory exactAmountsIn,
        address sender,
        WeightedPoolParams memory params
    ) external returns (IWeightedPool, uint256) {
        return _migrateLiquidity(lbp, exactAmountsIn, 0, new uint256[](exactAmountsIn.length), sender, params, true);
    }

    function migrateLiquidityHook(MigrationHookParams memory params) external onlyVault returns (uint256) {
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

            uint256 restAmount = removeAmountsOut[i] - params.exactAmountsIn[i];
            if (restAmount > 0) {
                _vault.sendTo(params.tokens[i], params.sender, restAmount);
            }
        }

        return
            _vault.initialize(
                address(params.weightedPool),
                params.sender,
                params.tokens,
                params.exactAmountsIn,
                params.minAddBptAmountOut,
                new bytes(0)
            );
    }

    function _migrateLiquidity(
        ILBPool lbp,
        uint256[] memory exactAmountsIn,
        uint256 minAddBptAmountOut,
        uint256[] memory minRemoveAmountsOut,
        address sender,
        WeightedPoolParams memory params,
        bool isQuery
    ) internal returns (IWeightedPool weightedPool, uint256 bptAmountOut) {
        {
            LBPoolImmutableData memory lbpImmutableData = lbp.getLBPoolImmutableData();

            // solhint-disable-next-line not-rely-on-time
            if (block.timestamp <= lbpImmutableData.endTime) {
                revert LBPWeightsNotFinalized(lbp);
            }
        }

        IERC20[] memory tokens = _vault.getPoolTokens(address(lbp));
        TokenConfig[] memory tokensConfig = new TokenConfig[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokensConfig[i] = TokenConfig({
                token: tokens[i],
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                paysYieldFees: false
            });
        }

        WeightedPoolParams memory _params = params;
        weightedPool = IWeightedPool(
            weightedPoolFactory.create(
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

        MigrationHookParams memory migrateHookParams = MigrationHookParams({
            lbp: lbp,
            weightedPool: weightedPool,
            tokens: tokens,
            sender: sender,
            exactAmountsIn: exactAmountsIn,
            minAddBptAmountOut: minAddBptAmountOut,
            minRemoveAmountsOut: minRemoveAmountsOut
        });
        if (isQuery) {
            bptAmountOut = abi.decode(
                vault.quote(abi.encodeCall(LBPMigrationRouter.migrateLiquidityHook, migrateHookParams)),
                (uint256)
            );
        } else {
            bptAmountOut = abi.decode(
                vault.unlock(abi.encodeCall(LBPMigrationRouter.migrateLiquidityHook, migrateHookParams)),
                (uint256)
            );
        }
    }
}
