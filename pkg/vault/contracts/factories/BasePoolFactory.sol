// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

// solhint-disable-next-line max-line-length
import { SingletonAuthentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/SingletonAuthentication.sol";

import { FactoryWidePauseWindow } from "./FactoryWidePauseWindow.sol";

/**
 * @notice Base contract for Pool factories.
 *
 * Pools are deployed from factories to allow third parties to reason about them. Unknown Pools may have arbitrary
 * logic: being able to assert that a Pool's behavior follows certain rules (those imposed by the contracts created by
 * the factory) is very powerful.
 *
 * Since we expect to release new versions of pool types regularly - and the blockchain is forever - versioning will
 * become increasingly important. Governance can deprecate a factory by calling `disable`, which will permanently
 * prevent the creation of any future pools from the factory.
 */
abstract contract BasePoolFactory is IBasePoolFactory, SingletonAuthentication, FactoryWidePauseWindow {
    mapping(address => bool) private _isPoolFromFactory;
    bool private _disabled;

    constructor(
        IVault vault,
        uint256 initialPauseWindowDuration
    ) SingletonAuthentication(vault) FactoryWidePauseWindow(initialPauseWindowDuration) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IBasePoolFactory
    function isPoolFromFactory(address pool) external view returns (bool) {
        return _isPoolFromFactory[pool];
    }

    /// @inheritdoc IBasePoolFactory
    function isDisabled() public view returns (bool) {
        return _disabled;
    }

    /// @inheritdoc IBasePoolFactory
    function disable() external authenticate {
        _ensureEnabled();

        _disabled = true;

        emit FactoryDisabled();
    }

    function _ensureEnabled() internal view {
        if (isDisabled()) {
            revert Disabled();
        }
    }

    function _registerPoolWithFactory(address pool) internal virtual {
        _ensureEnabled();

        _isPoolFromFactory[pool] = true;

        emit PoolCreated(pool);
    }
}
