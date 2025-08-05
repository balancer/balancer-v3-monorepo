// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { ITokenPairRegistry } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ITokenPairRegistry.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { EnumerableSet } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { OwnableAuthentication } from "./OwnableAuthentication.sol";

contract TokenPairRegistry is ITokenPairRegistry, OwnableAuthentication {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(bytes32 pairId => IBatchRouter.SwapPathStep[][] paths) internal _pairsToPaths;

    constructor(IVault vault, address initialOwner) OwnableAuthentication(vault, initialOwner) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getPathAt(
        address tokenA,
        address tokenB,
        uint256 index
    ) external view returns (IBatchRouter.SwapPathStep[] memory) {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);
        return _pairsToPaths[tokenId][index];
    }

    function getPathCount(address tokenA, address tokenB) external view returns (uint256) {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);
        return _pairsToPaths[tokenId].length;
    }

    function getPaths(address tokenA, address tokenB) external view returns (IBatchRouter.SwapPathStep[][] memory) {
        bytes32 tokenId = _getTokenId(tokenA, tokenB);
        return _pairsToPaths[tokenId];
    }

    function addPath(address tokenIn, IBatchRouter.SwapPathStep[] memory steps) external authenticate {
        address tokenOut = address(steps[steps.length - 1].tokenOut);
        bytes32 tokenId = _getTokenId(tokenIn, tokenOut);

        address stepTokenIn = tokenIn;
        for (uint256 i = 0; i < steps.length; ++i) {
            IBatchRouter.SwapPathStep memory step = steps[i];
            if (step.isBuffer) {
                _checkBufferStep(step.pool, stepTokenIn, address(step.tokenOut));
            } else {
                _checkPoolStep(step.pool, stepTokenIn, address(step.tokenOut));
            }

            // Update token in for the next iteration
            stepTokenIn = address(step.tokenOut);
        }

        IBatchRouter.SwapPathStep[][] storage paths = _pairsToPaths[tokenId];
        paths.push();
        for (uint256 i = 0; i < steps.length; ++i) {
            paths[paths.length - 1].push(steps[i]);
        }
        emit PathAdded(tokenIn, tokenOut, _pairsToPaths[tokenId].length);
    }

    function removePathAtIndex(address tokenIn, address tokenOut, uint256 index) external authenticate {
        bytes32 tokenId = _getTokenId(tokenIn, tokenOut);
        IBatchRouter.SwapPathStep[][] storage paths = _pairsToPaths[tokenId];
        uint256 pathsLength = paths.length;

        if (index >= pathsLength) {
            revert IndexOutOfBounds();
        }

        if (pathsLength > 1 && index != pathsLength - 1) {
            paths[index] = paths[pathsLength - 1];
        }
        // pop() can be used to clear dynamic arrays: it deletes every element and removes the inner array entirely.
        paths.pop();

        emit PathRemoved(tokenIn, tokenOut, paths.length);
    }

    function addSimplePath(address path) external authenticate {
        if (vault.isPoolRegistered(path)) {
            _addPool(path);
        } else if (vault.isERC4626BufferInitialized(IERC4626(path))) {
            _addBuffer(IERC4626(path));
        } else {
            revert InvalidSimplePath(path);
        }
    }

    function removeSimplePath(address path) external authenticate {
        if (vault.isPoolRegistered(path)) {
            _removePool(path);
        } else if (vault.isERC4626BufferInitialized(IERC4626(path))) {
            _removeBuffer(IERC4626(path));
        } else {
            revert InvalidSimplePath(path);
        }
    }

    function _addPool(address pool) internal {
        IERC20[] memory tokens = vault.getPoolTokens(pool);

        uint256 tokenPairs = tokens.length - 1;
        for (uint256 i = 0; i < tokenPairs; ++i) {
            for (uint256 j = i + 1; j < tokens.length; ++j) {
                _addTokenPair(pool, address(tokens[i]), address(tokens[j]), false);
            }
        }
    }

    /**
     * @dev The "pool" for (underlying, wrapped) shall be `wrapped` always, but only if it's registered as a vault
     * buffer.
     */
    function _addBuffer(IERC4626 wrappedToken) internal {
        address underlyingToken = vault.getBufferAsset(wrappedToken);
        _addTokenPair(address(wrappedToken), underlyingToken, address(wrappedToken), true);
    }

    function _addTokenPair(address pool, address tokenA, address tokenB, bool isBuffer) internal {
        _addSimplePairStep(pool, tokenA, tokenB, isBuffer);
        _addSimplePairStep(pool, tokenB, tokenA, isBuffer);
    }

    function _addSimplePairStep(address pool, address tokenIn, address tokenOut, bool isBuffer) internal {
        bytes32 tokenId = _getTokenId(tokenIn, tokenOut);
        IBatchRouter.SwapPathStep memory step = IBatchRouter.SwapPathStep({
            pool: pool,
            tokenOut: IERC20(tokenOut),
            isBuffer: isBuffer
        });

        IBatchRouter.SwapPathStep[][] storage paths = _pairsToPaths[tokenId];
        paths.push();
        paths[paths.length - 1].push(step);
        emit PathAdded(tokenIn, tokenOut, _pairsToPaths[tokenId].length);
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
        _removeSimplePairStep(pool, tokenA, tokenB);
        _removeSimplePairStep(pool, tokenB, tokenA);
    }

    function _removeSimplePairStep(address poolOrBuffer, address tokenIn, address tokenOut) internal {
        console.log('Remove pair step');
        bytes32 tokenId = _getTokenId(tokenIn, tokenOut);

        IBatchRouter.SwapPathStep[][] storage paths = _pairsToPaths[tokenId];
        bool elementRemoved = false;
        for (uint256 i = 0; i < paths.length; ++i) {
            IBatchRouter.SwapPathStep[] storage steps = paths[i];
            if (steps.length > 1) {
                console.log('## CONTINUE');
                continue;
            }

            if (steps[0].pool == poolOrBuffer && address(steps[0].tokenOut) == tokenOut) {
                console.log('found');
                if (paths.length > 1) {
                    console.log('arranging paths');
                    paths[i] = paths[paths.length - 1];
                }
                console.log('about to pop');
                elementRemoved = true;
                break;
            }
        }

        if (elementRemoved) {
            paths.pop();
            emit PathRemoved(tokenIn, tokenOut, paths.length);
        } else {
            revert InvalidRemovePath(poolOrBuffer, tokenIn, tokenOut);
        }
    }

    function _removeBuffer(IERC4626 wrappedToken) internal {
        address underlyingToken = vault.getBufferAsset(wrappedToken);
        _removeTokenPair(address(wrappedToken), underlyingToken, address(wrappedToken));
    }

    function _getTokenId(address tokenIn, address tokenOut) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenIn, tokenOut));
    }

    function _checkBufferStep(address buffer, address tokenIn, address tokenOut) internal view {
        address underlying = address(vault.getBufferAsset(IERC4626(buffer)));

        if (underlying == address(0)) {
            revert BufferNotInitialized(buffer);
        }

        if (tokenIn == underlying) {
            // This is a wrap
            if (tokenOut != address(buffer)) {
                revert InvalidBufferPath(buffer, tokenIn, tokenOut);
            }
        } else if (tokenIn == buffer) {
            // This is an unwrap
            if (tokenOut != address(underlying)) {
                revert InvalidBufferPath(buffer, tokenIn, tokenOut);
            }
        } else {
            // Token in must be either wrapped or underlying
            revert InvalidBufferPath(buffer, tokenIn, tokenOut);
        }
    }

    function _checkPoolStep(address pool, address tokenIn, address tokenOut) internal view {
        IERC20[] memory tokens = vault.getPoolTokens(pool);

        bool foundIn = false;
        bool foundOut = false;

        for (uint256 i = 0; i < tokens.length; ++i) {
            if (tokens[i] == IERC20(tokenIn)) {
                foundIn = true;
            }
            if (tokens[i] == IERC20(tokenOut)) {
                foundOut = true;
            }
        }

        if (!foundIn || !foundOut) {
            revert InvalidSimplePath(pool);
        }
    }
}
