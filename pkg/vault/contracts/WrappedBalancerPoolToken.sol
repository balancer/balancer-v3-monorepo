// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWrappedBalancerPoolToken } from "@balancer-labs/v3-interfaces/contracts/vault/IWrappedBalancerPoolToken.sol";

/**
 * @notice ERC20 wrapper for Balancer Pool Token (BPT).
 * @dev This allows users to deposit BPT and receive wrapped tokens 1:1, or burn wrapped tokens to redeem the original
 * amount of BPT.
 *
 * Minting and burning are only allowed when the Vault is locked.
 */
contract WrappedBalancerPoolToken is IWrappedBalancerPoolToken, ERC20, ERC20Permit {
    using SafeERC20 for *;

    IERC20 public immutable balancerPoolToken;
    IVault public immutable vault;

    constructor(
        IVault vault_,
        IERC20 balancerPoolToken_,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) ERC20Permit(name) {
        vault = vault_;
        balancerPoolToken = balancerPoolToken_;
    }

    modifier onlyIfVaultLocked() {
        if (vault.isUnlocked()) {
            revert VaultIsUnlocked();
        }
        _;
    }

    /// @inheritdoc IWrappedBalancerPoolToken
    function mint(uint256 amount) public onlyIfVaultLocked {
        balancerPoolToken.safeTransferFrom(msg.sender, address(this), amount);

        _mint(msg.sender, amount);
    }

    /// @inheritdoc IWrappedBalancerPoolToken
    function burn(uint256 value) public onlyIfVaultLocked {
        _burnAndTransfer(msg.sender, value);
    }

    /// @inheritdoc IWrappedBalancerPoolToken
    function burnFrom(address account, uint256 value) public onlyIfVaultLocked {
        _spendAllowance(account, msg.sender, value);

        _burnAndTransfer(account, value);
    }

    function _burnAndTransfer(address account, uint256 value) internal {
        _burn(account, value);

        balancerPoolToken.transfer(account, value);
    }
}
