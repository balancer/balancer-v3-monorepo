// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { LBPParams } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { LBPoolFactory } from "../../../contracts/lbp/LBPoolFactory.sol";
import { LBPoolContractsDeployer } from "./LBPoolContractsDeployer.sol";

contract BaseLBPTest is BaseVaultTest, LBPoolContractsDeployer {
    using ArrayHelpers for *;

    uint256 public constant swapFee = 1e16; // 1%

    string public constant factoryVersion = "Factory v1";
    string public constant poolVersion = "Pool v1";

    uint256 internal constant HIGH_WEIGHT = uint256(70e16);
    uint256 internal constant LOW_WEIGHT = uint256(30e16);
    uint32 internal constant DEFAULT_START_OFFSET = 100;
    uint32 internal constant DEFAULT_END_OFFSET = 200;
    bool internal constant DEFAULT_PROJECT_TOKENS_SWAP_IN = false;

    IERC20 internal projectToken;
    IERC20 internal reserveToken;

    uint256[] internal startWeights;
    uint256[] internal endWeights;
    uint256 internal projectIdx;
    uint256 internal reserveIdx;

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
            address(router),
            permit2
        );
        vm.label(address(lbPoolFactory), "LB pool factory");

        // Approve dai and usdc for factory, so it can initialize the LBPool.
        vm.startPrank(bob);
        dai.approve(address(lbPoolFactory), poolInitAmount);
        usdc.approve(address(lbPoolFactory), poolInitAmount);
        vm.stopPrank();

        return address(lbPoolFactory);
    }

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        return
            _deployAndInitializeLBPool(
                uint32(block.timestamp + DEFAULT_START_OFFSET),
                uint32(block.timestamp + DEFAULT_END_OFFSET),
                DEFAULT_PROJECT_TOKENS_SWAP_IN
            );
    }

    function initPool() internal pure override {
        // Init is not used because LBPool factory creates and initializes the pool in the same function.
        return;
    }

    function _deployAndInitializeLBPool(
        uint32 startTime,
        uint32 endTime,
        bool enableProjectTokenSwapsIn
    ) internal returns (address newPool, bytes memory poolArgs) {
        string memory name = "LBPool";
        string memory symbol = "LBP";

        LBPParams memory lbpParams = LBPParams({
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            projectTokenStartWeight: startWeights[projectIdx],
            reserveTokenStartWeight: startWeights[reserveIdx],
            projectTokenEndWeight: endWeights[projectIdx],
            reserveTokenEndWeight: endWeights[reserveIdx],
            startTime: startTime,
            endTime: endTime,
            enableProjectTokenSwapsIn: enableProjectTokenSwapsIn
        });

        vm.prank(bob);
        newPool = lbPoolFactory.createAndInitialize(
            name,
            symbol,
            lbpParams,
            swapFee,
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            ZERO_BYTES32
        );

        poolArgs = abi.encode(name, symbol, lbpParams, vault, address(router), address(lbPoolFactory), poolVersion);
    }
}
