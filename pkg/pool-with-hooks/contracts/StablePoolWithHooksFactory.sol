// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig, LiquidityManagement } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { BasePoolFactory } from "@balancer-labs/v3-vault/contracts/factories/BasePoolFactory.sol";
import { StablePool } from "@balancer-labs/v3-pool-stable/contracts/StablePool.sol";

import { BaseHooks } from "./BaseHooks.sol";
import { StablePoolWithHooks } from "./StablePoolWithHooks.sol";

/**
 * @title StablePoolWithHooksFactory
 * @notice The contract allows deploying a Stable Pool with an attached hooks contract.
 */
contract StablePoolWithHooksFactory is BasePoolFactory {
    error InvalidHooksContract();

    constructor(
        IVault vault,
        uint256 pauseWindowDuration
    ) BasePoolFactory(vault, pauseWindowDuration, type(StablePoolWithHooks).creationCode) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Deploys a new `StablePoolWithHooks` and `CustomHooks` contracts
     * @dev Tokens must be sorted for pool registration.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param tokens An array of descriptors for the tokens the pool will manage
     * @param amplificationParameter The starting Amplification Parameter
     * @param swapFeePercentage Initial swap fee percentage
     * @param salt The salt value that will be passed to create3 deployment
     * @param pauseManager The address of the pause manager
     * @param hooksBytecode The bytecode of new hooks contract
     * @param hooksEncodedParams The encoded parameters for the hooks contract
     */
    function create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokens,
        uint256 amplificationParameter,
        uint256 swapFeePercentage,
        bytes32 salt,
        address pauseManager,
        bytes memory hooksBytecode,
        bytes memory hooksEncodedParams
    ) external returns (address pool, address hooks) {
        pool = _create(
            abi.encode(
                StablePool.NewPoolParams({
                    name: name,
                    symbol: symbol,
                    amplificationParameter: amplificationParameter
                }),
                getVault(),
                abi.encodePacked(hooksBytecode, hooksEncodedParams),
                // Same safe salt for both the pool and the hooks contract
                salt
            ),
            salt
        );

        hooks = StablePoolWithHooks(pool).hooksAddress();

        BaseHooks hooksContract = BaseHooks(hooks);
        if (pool != hooksContract.authorizedPool()) {
            revert InvalidHooksContract();
        }

        getVault().registerPool(
            pool,
            tokens,
            swapFeePercentage,
            getNewPoolPauseWindowEndTime(),
            pauseManager,
            address(0), // no pool creator
            hooksContract.availableHooks(),
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: false,
                enableRemoveLiquidityCustom: false
            }),
            hooksContract.supportsDynamicFee()
        );

        _registerPoolWithFactory(pool);
    }
}
