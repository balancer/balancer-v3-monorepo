// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { LBPParams } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { LBPoolFactory } from "../../../contracts/lbp/LBPoolFactory.sol";
import { LBPoolContractsDeployer } from "./LBPoolContractsDeployer.sol";

contract BaseLBPTest is BaseVaultTest, LBPoolContractsDeployer {
    using ArrayHelpers for *;
    using CastingHelpers for *;

    uint256 public constant swapFee = 1e16; // 1%

    string public constant factoryVersion = "Factory v1";
    string public constant poolVersion = "Pool v1";

    uint256 internal constant HIGH_WEIGHT = uint256(70e16);
    uint256 internal constant LOW_WEIGHT = uint256(30e16);
    uint32 internal constant DEFAULT_START_OFFSET = 100;
    uint32 internal constant DEFAULT_END_OFFSET = 200;
    bool internal constant DEFAULT_PROJECT_TOKENS_SWAP_IN = true;

    IERC20 internal projectToken;
    IERC20 internal reserveToken;

    uint256[] internal startWeights;
    uint256[] internal endWeights;
    uint256 internal projectIdx;
    uint256 internal reserveIdx;

    uint256 private _saltCounter;

    LBPoolFactory internal lbPoolFactory;

    function onAfterDeployMainContracts() internal override {
        projectToken = dai;
        reserveToken = usdc;

        (projectIdx, reserveIdx) = getSortedIndexes(address(projectToken), address(reserveToken));

        startWeights = new uint256[](2);
        startWeights[projectIdx] = HIGH_WEIGHT;
        startWeights[reserveIdx] = LOW_WEIGHT;

        endWeights = new uint256[](2);
        endWeights[projectIdx] = LOW_WEIGHT;
        endWeights[reserveIdx] = HIGH_WEIGHT;
    }

    function createPoolFactory() internal override returns (address) {
        lbPoolFactory = deployLBPoolFactory(
            IVault(address(vault)),
            365 days,
            factoryVersion,
            poolVersion,
            address(router)
        );
        vm.label(address(lbPoolFactory), "LB pool factory");

        return address(lbPoolFactory);
    }

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        return
            _createLBPool(
                uint32(block.timestamp + DEFAULT_START_OFFSET),
                uint32(block.timestamp + DEFAULT_END_OFFSET),
                DEFAULT_PROJECT_TOKENS_SWAP_IN
            );
    }

    function initPool() internal override {
        vm.startPrank(bob); // Bob is the owner of the pool.
        _initPool(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();
    }

    function _createLBPool(
        uint32 startTime,
        uint32 endTime,
        bool blockProjectTokenSwapsIn
    ) internal returns (address newPool, bytes memory poolArgs) {
        return
            _createLBPoolWithCustomWeights(
                startWeights[projectIdx],
                startWeights[reserveIdx],
                endWeights[projectIdx],
                endWeights[reserveIdx],
                startTime,
                endTime,
                blockProjectTokenSwapsIn
            );
    }

    function _createLBPoolWithCustomWeights(
        uint256 projectTokenStartWeight,
        uint256 reserveTokenStartWeight,
        uint256 projectTokenEndWeight,
        uint256 reserveTokenEndWeight,
        uint32 startTime,
        uint32 endTime,
        bool blockProjectTokenSwapsIn
    ) internal returns (address newPool, bytes memory poolArgs) {
        string memory name = "LBPool";
        string memory symbol = "LBP";

        LBPParams memory lbpParams = LBPParams({
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            projectTokenStartWeight: projectTokenStartWeight,
            reserveTokenStartWeight: reserveTokenStartWeight,
            projectTokenEndWeight: projectTokenEndWeight,
            reserveTokenEndWeight: reserveTokenEndWeight,
            startTime: startTime,
            endTime: endTime,
            blockProjectTokenSwapsIn: blockProjectTokenSwapsIn
        });

        newPool = lbPoolFactory.create(name, symbol, lbpParams, swapFee, bytes32(_saltCounter++));

        poolArgs = abi.encode(name, symbol, lbpParams, vault, address(router), address(lbPoolFactory), poolVersion);
    }
}
