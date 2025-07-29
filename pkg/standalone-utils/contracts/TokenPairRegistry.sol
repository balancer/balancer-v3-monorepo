// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { EnumerableSet } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { OwnableAuthentication } from "./OwnableAuthentication.sol";

contract TokenPairRegistry is OwnableAuthentication {
    using EnumerableSet for EnumerableSet.AddressSet;

    event TokenPairAdded(address indexed pool, address indexed tokenA, address indexed tokenB);

    event TokenPairRemoved(address indexed pool, address indexed tokenA, address indexed tokenB);

    error WrongTokenOrder();

    error PoolAlreadyAddedForPair(address pool, address tokenA, address tokenB);

    error PoolNotAddedForPair(address pool, address tokenA, address tokenB);

    mapping(bytes32 pairId => EnumerableSet.AddressSet pools) internal pairsToPool;

    constructor(IVault vault, address initialOwner) OwnableAuthentication(vault, initialOwner) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getPoolAt(address tokenA, address tokenB, uint256 index) external view returns (address) {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);
        return pairsToPool[tokenId].at(index);
    }

    function getPoolAtUnchecked(address tokenA, address tokenB, uint256 index) external view returns (address) {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);
        return pairsToPool[tokenId].unchecked_at(index);
    }

    function getPoolCount(address tokenA, address tokenB) external view returns (uint256) {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);
        return pairsToPool[tokenId].length();
    }

    function getPools(address tokenA, address tokenB) external view returns (address[] memory) {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);
        EnumerableSet.AddressSet storage pools = pairsToPool[tokenId];
        return pools._values;
    }

    function hasPool(address tokenA, address tokenB, address pool) external view returns (bool) {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);
        return pairsToPool[tokenId].contains(pool);
    }

    function addPool(address pool) external authenticate {
        // This call reverts if the pool is not registered.
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
    function addBuffer(IERC4626 wrappedToken) external authenticate {
        address underlyingToken = vault.getBufferAsset(wrappedToken);
        _addTokenPair(address(wrappedToken), underlyingToken, address(wrappedToken));
    }

    function removePool(address pool) external authenticate {
        // This call reverts if the pool is not registered.
        IERC20[] memory tokens = vault.getPoolTokens(pool);

        uint256 tokenPairs = tokens.length - 1;
        for (uint256 i = 0; i < tokenPairs; ++i) {
            for (uint256 j = i + 1; j < tokens.length; ++j) {
                _removeTokenPair(pool, address(tokens[i]), address(tokens[j]));
            }
        }
    }

    function removeBuffer(IERC4626 wrappedToken) external authenticate {
        address underlyingToken = vault.getBufferAsset(wrappedToken);
        _removeTokenPair(address(wrappedToken), underlyingToken, address(wrappedToken));
    }

    function _addTokenPair(address pool, address tokenA, address tokenB) internal {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);

        if (pairsToPool[tokenId].add(pool) == false) {
            revert PoolAlreadyAddedForPair(pool, tokenA, tokenB);
        }
        emit TokenPairAdded(pool, tokenA, tokenB);
    }

    function _removeTokenPair(address pool, address tokenA, address tokenB) internal {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);

        if (pairsToPool[tokenId].remove(pool) == false) {
            revert PoolNotAddedForPair(pool, tokenA, tokenB);
        }
        emit TokenPairRemoved(pool, tokenA, tokenB);
    }

    /// @dev Returns a unique identifier for the token pair, ensuring that the order of tokens does not matter.
    function _getTokenId(address tokenA, address tokenB) internal pure returns (bytes32) {
        (tokenA, tokenB) = tokenA <= tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encodePacked(tokenA, tokenB));
    }
}
