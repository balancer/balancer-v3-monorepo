// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

/**
 * @notice Base for pool hooks contracts.
 * @dev Hook contracts that only implement a subset of callbacks can inherit from here instead of IHooks,
 * and only override what they need.
 *
 * If _isSecondaryHook is true, it means this hook is being added to a pool type that registered itself as the
 * "primary" hook (i.e., the hook contract that will be called directly by the Vault). In that case, the pool will
 * forward the `onRegister` call to this contract, so we set `_authorizedCaller` to msg.sender, which will be the pool
 * address.
 *
 * If _isSecondaryHook is false, it means this hook is being added to a pool type that is not itself a hook.
 * In that case, the Vault will call this hook contract directly, so we set `_authorizedCaller` to the Vault address.
 * If the derived hook contract does not set `_authorizedCaller`, it will be the zero address, and deployment will
 * revert.
 *
 * Note that in both cases we are setting `_authorizedCaller` to msg.sender, but if we simply did that (without the
 * flag), anyone could front-run the deployment transaction and become the authorized caller, at least in cases where
 * the hook is deployed separately from the pool (e.g., not atomically in a factory create function). We must ensure
 * that primary hook contracts can only be called by the Vault.
 *
 * This also avoids the chicken-and-egg problem of not knowing the pool address at deployment time, which we would
 * encounter if we tried to make `_authorizedCaller` immutable and set it in the constructor. There is a trade-off here
 * between the gas cost of the extra storage read to check the caller on each hook call, and the convenience of setting
 * the authorized caller on registration.
 */
abstract contract BaseHooks is IHooks {
    bool internal immutable _isSecondaryHook;

    // The address authorized to call non-view hook functions. Set during hook registration.
    address internal _authorizedCaller;

    modifier onlyAuthorizedCaller() {
        _ensureOnlyAuthorizedCaller();
        _;
    }

    constructor(bool isSecondaryHook_) {
        _isSecondaryHook = isSecondaryHook_;
    }

    /// @inheritdoc IHooks
    function onRegister(
        address,
        address,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public virtual returns (bool) {
        // By default, deny all factories. This method must be overwritten by the hook contract.
        return false;
    }

    /// @inheritdoc IHooks
    function getHookFlags() public view virtual returns (HookFlags memory);

    /// @inheritdoc IHooks
    function onBeforeInitialize(uint256[] memory, bytes memory) public virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IHooks
    function onAfterInitialize(uint256[] memory, uint256, bytes memory) public virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IHooks
    function onBeforeAddLiquidity(
        address,
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IHooks
    function onAfterAddLiquidity(
        address,
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256[] memory amountsInRaw,
        uint256,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bool, uint256[] memory) {
        return (false, amountsInRaw);
    }

    /// @inheritdoc IHooks
    function onBeforeRemoveLiquidity(
        address,
        address,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IHooks
    function onAfterRemoveLiquidity(
        address,
        address,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory amountsOutRaw,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bool, uint256[] memory) {
        return (false, amountsOutRaw);
    }

    /// @inheritdoc IHooks
    function onBeforeSwap(PoolSwapParams calldata, address) public virtual returns (bool) {
        // return false to trigger an error if shouldCallBeforeSwap is true but this function is not overridden.
        return false;
    }

    /// @inheritdoc IHooks
    function onAfterSwap(AfterSwapParams calldata) public virtual returns (bool, uint256) {
        // return false to trigger an error if shouldCallAfterSwap is true but this function is not overridden.
        // The second argument is not used.
        return (false, 0);
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata,
        address,
        uint256
    ) public view virtual returns (bool, uint256) {
        return (false, 0);
    }

    /// @inheritdoc IHooks
    function isSecondaryHook() external view returns (bool) {
        return _isSecondaryHook;
    }

    /// @inheritdoc IHooks
    function getAuthorizedCaller() external view returns (address) {
        return _authorizedCaller;
    }

    function _ensureOnlyAuthorizedCaller() internal view {
        require(msg.sender == _authorizedCaller, HookCallerNotAuthorized(msg.sender, _authorizedCaller));
    }

    function _setAuthorizedCaller(address factory, address pool, address vault) internal {
        address authorizedCaller = _isSecondaryHook ? pool : vault;

        require(msg.sender == authorizedCaller, HookCallerNotAuthorized(msg.sender, authorizedCaller));

        _enforceFactoryConstraints(factory, pool);

        // For primary hooks, the authorized caller is always the vault, so re-registration with a
        // different pool is safe. For secondary hooks, the authorized caller is the pool address,
        // which will differ between pools, so this check still enforces one-pool-per-hook.
        if (_authorizedCaller != authorizedCaller) {
            require(_authorizedCaller == address(0), AuthorizedCallerAlreadySet());

            _authorizedCaller = authorizedCaller;
        }
    }

    /**
     * @notice For hooks that require it, ensure that the secondary hook's pool was deployed by a trusted factory.
     * @dev Would be stricter to revert by default, but that would force all hooks to override it.
     * @param factory The factory address passed into `_setAuthorizedCaller`.
     * @param pool The pool address passed into `_setAuthorizedCaller`.
     */
    function _enforceFactoryConstraints(address factory, address pool) internal view virtual {
        // solhint-disable-previous-line no-empty-blocks
    }
}
