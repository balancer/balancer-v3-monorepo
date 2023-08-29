// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { Config } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

library ConfigLib {
    // Bitwise flags for pool's config
    uint256 public constant POOL_REGISTERED_FLAG = 1 << 0;
    uint256 public constant AFTER_SWAP_FLAG = 1 << 1;

    function addFlags(Config config, uint256 flags) internal pure returns (Config) {
        return Config.wrap(Config.unwrap(config) | flags);
    }

    function shouldCallAfterSwap(Config config) internal pure returns (bool) {
        return Config.unwrap(config) & AFTER_SWAP_FLAG != 0;
    }

    function addRegistration(Config config) internal pure returns (Config) {
        return Config.wrap(Config.unwrap(config) | POOL_REGISTERED_FLAG);
    }

    function isPoolRegistered(Config config) internal pure returns (bool) {
        return Config.unwrap(config) & POOL_REGISTERED_FLAG != 0;
    }
}
