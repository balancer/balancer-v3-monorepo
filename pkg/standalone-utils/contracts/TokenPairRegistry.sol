// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ITokenPairRegistry } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ITokenPairRegistry.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { EnumerableSet } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { OwnableAuthentication } from "./OwnableAuthentication.sol";

contract TokenPairRegistry is ITokenPairRegistry, OwnableAuthentication {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(bytes32 pairId => EnumerableSet.AddressSet pools) internal pairsToPath;

    constructor(IVault vault, address initialOwner) OwnableAuthentication(vault, initialOwner) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getPathAt(address tokenA, address tokenB, uint256 index) external view returns (address) {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);
        return pairsToPath[tokenId].at(index);
    }

    function getPathAtUnchecked(address tokenA, address tokenB, uint256 index) external view returns (address) {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);
        return pairsToPath[tokenId].unchecked_at(index);
    }

    function getPathCount(address tokenA, address tokenB) external view returns (uint256) {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);
        return pairsToPath[tokenId].length();
    }

    function getPaths(address tokenA, address tokenB) external view returns (address[] memory) {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);
        EnumerableSet.AddressSet storage pools = pairsToPath[tokenId];
        return pools._values;
    }

    function hasPath(address tokenA, address tokenB, address pool) external view returns (bool) {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);
        return pairsToPath[tokenId].contains(pool);
    }

    function addPath(address path) external authenticate {
        if (vault.isPoolRegistered(path)) {
            _addPool(path);
        } else if (vault.isERC4626BufferInitialized(IERC4626(path))) {
            _addBuffer(IERC4626(path));
        } else {
            revert InvalidPath(path);
        }
    }

    function removePath(address path) external authenticate {
        if (vault.isPoolRegistered(path)) {
            _removePool(path);
        } else if (vault.isERC4626BufferInitialized(IERC4626(path))) {
            _removeBuffer(IERC4626(path));
        } else {
            revert InvalidPath(path);
        }
    }

    function _addPool(address pool) internal {
        IERC20[] memory tokens = vault.getPoolTokens(pool);

        uint256 tokenPairs = tokens.length - 1;
        for (uint256 i = 0; i < tokenPairs; ++i) {
            for (uint256 j = i + 1; j < tokens.length; ++j) {
                _addTokenPair(pool, address(tokens[i]), address(tokens[j]));
            }
        }
    }

    /**
     * @dev The "pool" for (underlying, wrapped) shall be `wrapped` always, but only if it's registered as a vault
     * buffer.
     */
    function _addBuffer(IERC4626 wrappedToken) internal {
        address underlyingToken = vault.getBufferAsset(wrappedToken);
        _addTokenPair(address(wrappedToken), underlyingToken, address(wrappedToken));
    }

    function _addTokenPair(address pool, address tokenA, address tokenB) internal {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);

        if (pairsToPath[tokenId].add(pool) == false) {
            revert PathAlreadyAddedForPair(pool, tokenA, tokenB);
        }
        emit TokenPairAdded(pool, tokenA, tokenB);
    }

    function _removePool(address pool) internal {
        IERC20[] memory tokens = vault.getPoolTokens(pool);

        uint256 tokenPairs = tokens.length - 1;
        for (uint256 i = 0; i < tokenPairs; ++i) {
            for (uint256 j = i + 1; j < tokens.length; ++j) {
                _removeTokenPair(pool, address(tokens[i]), address(tokens[j]));
            }
        }
    }

    function _removeTokenPair(address pool, address tokenA, address tokenB) internal {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);

        if (pairsToPath[tokenId].remove(pool) == false) {
            revert PathNotAddedForPair(pool, tokenA, tokenB);
        }
        emit TokenPairRemoved(pool, tokenA, tokenB);
    }

    function _removeBuffer(IERC4626 wrappedToken) internal {
        address underlyingToken = vault.getBufferAsset(wrappedToken);
        _removeTokenPair(address(wrappedToken), underlyingToken, address(wrappedToken));
    }

    /// @dev Returns a unique identifier for the token pair, ensuring that the order of tokens does not matter.
    function _getTokenId(address tokenA, address tokenB) internal pure returns (bytes32) {
        (tokenA, tokenB) = tokenA <= tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encodePacked(tokenA, tokenB));
    }
}
