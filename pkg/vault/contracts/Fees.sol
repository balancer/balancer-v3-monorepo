// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";
import "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/SafeERC20.sol";

import "./ProtocolFeesCollector.sol";
import "./VaultAuthorization.sol";

/**
 * @dev To reduce the bytecode size of the Vault, most of the protocol fee logic is not here, but in the
 * ProtocolFeesCollector contract.
 */
abstract contract Fees is IVault {
    using SafeERC20 for IERC20;

    ProtocolFeesCollector private immutable _protocolFeesCollector;

    constructor() {
        _protocolFeesCollector = new ProtocolFeesCollector(IVault(this));
    }

    function getProtocolFeesCollector() public view override returns (IProtocolFeesCollector) {
        return _protocolFeesCollector;
    }

    /**
     * @dev Returns the protocol swap fee percentage.
     */
    function _getProtocolSwapFeePercentage() internal view returns (uint256) {
        return getProtocolFeesCollector().getSwapFeePercentage();
    }

    function _payFeeAmount(IERC20 token, uint256 amount) internal {
        if (amount > 0) {
            token.safeTransfer(address(getProtocolFeesCollector()), amount);
        }
    }
}
