// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.0;

import "@balancer-labs/v3-interfaces/contracts/liquidity-mining/IAuthorizerAdaptor.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

contract MockAuthorizerAdaptorEntrypoint {
    function getVault() external pure returns (IVault) {
        return IVault(0);
    }

    function getAuthorizerAdaptor() external pure returns (IAuthorizerAdaptor) {
        return IAuthorizerAdaptor(0);
    }
}
