// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";

type Asset is address;

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

    /// @dev Same as `_translateToIERC20(Asset)`, but for an entire array.
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

    /// @dev Returns tokens as an array IERC20[] memory
    function asIERC20(address[] memory tokens) internal pure returns (IERC20[] memory assets) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            assets := tokens
        }
    }

    /// @dev Returns tokens as an array of address[] memory
    function asAddress(IERC20[] memory tokens) internal pure returns (address[] memory assets) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            assets := tokens
        }
    }
}
