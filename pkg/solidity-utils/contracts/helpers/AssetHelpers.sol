// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { Asset } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/Asset.sol";

library AssetHelpers {
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
        return isETH(asset) ? weth : asIERC20(asset);
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

    /// @dev Returns an address as an Asset
    function asAsset(address addr) internal pure returns (Asset asset) {
        return Asset.wrap(addr);
    }
}
