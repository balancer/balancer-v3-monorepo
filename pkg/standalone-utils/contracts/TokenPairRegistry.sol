// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { OwnableAuthentication } from "./OwnableAuthentication.sol";

contract TokenPairRegistry is OwnableAuthentication {
    event TokenPairRegistered(address indexed pool, address indexed tokenA, address indexed tokenB);

    error WrongTokenOrder();

    mapping (bytes32 pairId => address pool) internal pairsToPool;

    constructor(IVault vault, address initialOwner) OwnableAuthentication(vault, initialOwner) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getPool(address tokenA, address tokenB) external view returns (address) {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);
        return pairsToPool[tokenId];
    }

    function addPool(address pool) external authenticate {
        // This call reverts if the pool is not registered.
        IERC20[] memory tokens = vault.getPoolTokens(pool);

        uint256 tokenPairs = tokens.length - 1;
        for (uint256 i = 0; i < tokenPairs; ++i) {
            for (uint256 j = i + 1; j < tokens.length; ++j) {
                _registerTokenPair(pool, address(tokens[i]), address(tokens[j]));
            }
        }
    }

    /**
     * @dev The "pool" for (underlying, wrapped) shall be `wrapped` always, but only if it's registered as a vault
     * buffer. 
     */
    function addBuffer(IERC4626 wrappedToken) external authenticate {
        address underlyingToken = vault.getBufferAsset(wrappedToken);
        _registerTokenPair(address(wrappedToken), underlyingToken, address(wrappedToken));
    }

    function _registerTokenPair(address pool, address tokenA, address tokenB) internal {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);

        pairsToPool[tokenId] = pool;
        emit TokenPairRegistered(pool, tokenA, tokenB);
    }

    /// @dev Returns a unique identifier for the token pair, ensuring that the order of tokens does not matter.
    function _getTokenId(address tokenA, address tokenB) internal pure returns (bytes32) {
        (tokenA, tokenB) = tokenA <= tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encodePacked(tokenA, tokenB));
    }
}
