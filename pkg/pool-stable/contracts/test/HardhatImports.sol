// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

// This file is needed to compile artifacts from another repository using Hardhat.
import { VaultMock } from "@balancer-labs/v3-vault/contracts/test/VaultMock.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-vault/contracts/test/BasicAuthorizerMock.sol";
import { VaultAdminMock } from "@balancer-labs/v3-vault/contracts/test/VaultAdminMock.sol";
import { VaultExtensionMock } from "@balancer-labs/v3-vault/contracts/test/VaultExtensionMock.sol";
import { ProtocolFeeControllerMock } from "@balancer-labs/v3-vault/contracts/test/ProtocolFeeControllerMock.sol";
import { RouterMock } from "@balancer-labs/v3-vault/contracts/test/RouterMock.sol";
import { BatchRouterMock } from "@balancer-labs/v3-vault/contracts/test/BatchRouterMock.sol";
import { BufferRouterMock } from "@balancer-labs/v3-vault/contracts/test/BufferRouterMock.sol";
import { MevRouterMock } from "@balancer-labs/v3-vault/contracts/test/MevRouterMock.sol";
import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
