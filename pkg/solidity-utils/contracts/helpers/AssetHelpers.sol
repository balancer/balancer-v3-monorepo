// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { Asset } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/Asset.sol";

library AssetHelpers {
    using Address for address payable;
    using AssetHelpers for *;
    using SafeERC20 for IERC20;

    /**
     * @dev
     */
    error InsufficientEth();

    // Sentinel value used to indicate WETH with wrapping/unwrapping semantics. The zero address is a good choice for
    // multiple reasons: it is cheap to pass as a calldata argument, it is a known invalid token and non-contract, and
    // it is an address Pools cannot register as a token.
    Asset public constant NATIVE = Asset.wrap(address(0));

    /// @dev Returns true if `asset` is equal to `other`.
    function equals(Asset asset, Asset other) internal pure returns (bool) {
        return Asset.unwrap(asset) == Asset.unwrap(other);
    }

    /// @dev Returns true if `asset` is the sentinel value that represents ETH.
    function isETH(Asset asset) internal pure returns (bool) {
        return Asset.unwrap(asset) == Asset.unwrap(NATIVE);
    }

    /**
     * @dev Translates `asset` into an equivalent IERC20 token address. If `asset` represents ETH, it will be translated
     * to the WETH contract.
     */
    function toIERC20(Asset asset, IWETH weth) internal pure returns (IERC20) {
        return asset.isETH() ? weth : asIERC20(asset);
    }

    /// @dev Same as `toIERC20(Asset)`, but for an array.
    function toIERC20(Asset[] memory assets, IWETH weth) internal pure returns (IERC20[] memory) {
        IERC20[] memory tokens = new IERC20[](assets.length);
        for (uint256 i = 0; i < assets.length; ++i) {
            tokens[i] = toIERC20(assets[i], weth);
        }
        return tokens;
    }

    /**
     * @dev Interprets `asset` as an IERC20 token. This function should only be called on `asset` if `_isETH` previously
     * returned false for it, that is, if `asset` is guaranteed not to be the ETH sentinel value.
     */
    function asIERC20(Asset asset) internal pure returns (IERC20) {
        return IERC20(address(Asset.unwrap(asset)));
    }

    /// @dev Returns addresses as an array IERC20[] memory
    function asIERC20(address[] memory addresses) internal pure returns (IERC20[] memory tokens) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            tokens := addresses
        }
    }

    /// @dev Returns assets as an array of address[] memory
    function asAddress(Asset[] memory assets) internal pure returns (address[] memory addresses) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            addresses := assets
        }
    }

    /// @dev Returns tokens as an array of address[] memory
    function asAddress(IERC20[] memory tokens) internal pure returns (address[] memory addresses) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            addresses := tokens
        }
    }

    /// @dev Returns addresses as an array of Asset[] memory
    function asAsset(address[] memory addresses) internal pure returns (Asset[] memory assets) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            assets := addresses
        }
    }

    /// @dev Returns an IERC20 as an Asset
    function asAsset(IERC20 addr) internal pure returns (Asset asset) {
        return Asset.wrap(address(addr));
    }

    /// @dev Returns an address as an Asset
    function asAsset(address addr) internal pure returns (Asset asset) {
        return Asset.wrap(addr);
    }

    /// @dev Returns balance of the asset for `this`
    function balanceOf(Asset asset) internal view returns (uint256) {
        if (asset.isETH()) {
            return address(this).balance;
        } else {
            return IERC20(address(Asset.unwrap(asset))).balanceOf(address(this));
        }
    }

    /**
     * @dev Receives `amount` of `asset` from `sender`. If `fromInternalBalance` is true, it first withdraws as much
     * as possible from Internal Balance, then transfers any remaining amount.
     *
     * If `asset` is ETH, `fromInternalBalance` must be false (as ETH cannot be held as internal balance), and the funds
     * will be wrapped into WETH.
     *
     * WARNING: this function does not check that the contract caller has actually supplied any ETH - it is up to the
     * caller of this function to check that this is true to prevent the Vault from using its own ETH (though the Vault
     * typically doesn't hold any).
     */
    function retrieve(
        Asset asset,
        uint256 amount,
        address sender,
        IWETH weth
    ) internal {
        if (amount == 0) {
            return;
        }

        if (asset.isETH()) {
            // The ETH amount to receive is deposited into the WETH contract, which will in turn mint WETH for
            // the Vault at a 1:1 ratio.

            // A check for this condition is also introduced by the compiler, but this one provides a revert reason.
            // Note we're checking for the Vault's total balance, *not* ETH sent in this transaction.
            if (address(this).balance < amount) {
                revert InsufficientEth();
            }
            weth.deposit{ value: amount }();
        } else {
            IERC20 token = asset.asIERC20();

            token.safeTransferFrom(sender, address(this), amount);
        }
    }

    /**
     * @dev Sends `amount` of `asset` to `recipient`. If `toInternalBalance` is true, the asset is deposited as Internal
     * Balance instead of being transferred.
     *
     * If `asset` is ETH, `toInternalBalance` must be false (as ETH cannot be held as internal balance), and the funds
     * are instead sent directly after unwrapping WETH.
     */
    function send(
        Asset asset,
        address recipient,
        uint256 amount,
        IWETH weth
    ) internal {
        if (amount == 0) {
            return;
        }

        if (asset.isETH()) {
            // First, the Vault withdraws deposited ETH from the WETH contract, by burning the same amount of WETH
            // from the Vault. This receipt will be handled by the Vault's `receive`.
            weth.withdraw(amount);

            // Then, the withdrawn ETH is sent to the recipient.
            payable(recipient).sendValue(amount);
        } else {
            asset.asIERC20().safeTransfer(recipient, amount);
        }
    }

    /**
     * @dev Returns excess ETH back to the contract caller, assuming `amountUsed` has been spent. Reverts
     * if the caller sent less ETH than `amountUsed`.
     *
     * Because the caller might not know exactly how much ETH a Vault action will require, they may send extra.
     * Note that this excess value is returned *to the contract caller* (msg.sender). If caller and e.g. swap sender are
     * not the same (because the caller is a relayer for the sender), then it is up to the caller to manage this
     * returned ETH.
     */
    function returnEth(address sender, uint256 amountUsed) internal {
        if (msg.value < amountUsed) {
            revert InsufficientEth();
        }

        uint256 excess = msg.value - amountUsed;
        if (excess > 0) {
            payable(sender).sendValue(excess);
        }
    }
}
