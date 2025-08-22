// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { HyperTokenInfoPrecompile } from "../../contracts/utils/HyperTokenInfoPrecompile.sol";
import { HyperSpotPricePrecompile } from "../../contracts/utils/HyperSpotPricePrecompile.sol";
import { HypercorePrecompileMock } from "./utils/HypercorePrecompileMock.sol";

contract HyperEVMPrecompileMocksTest is Test {
    bytes internal constant ALPHABET = "0123456789abcdef";

    function testTokenInfoPrecompile() public {
        uint32 uethIndex = 221;
        // `cast call` the precompile to get the onchain data.
        bytes memory data = _ffiPrecompile(HyperTokenInfoPrecompile.TOKEN_INFO_PRECOMPILE_ADDRESS, uethIndex);
        // Store the szDecimals of the UETH token, as returned by the precompile.
        uint256 originalSzDecimals = abi.decode(data, (HyperTokenInfoPrecompile.HyperTokenInfo)).szDecimals;

        // Mock the precompile.
        vm.etch(HyperTokenInfoPrecompile.TOKEN_INFO_PRECOMPILE_ADDRESS, address(new HypercorePrecompileMock()).code);
        // Set the onchain data to the mock.
        HypercorePrecompileMock(HyperTokenInfoPrecompile.TOKEN_INFO_PRECOMPILE_ADDRESS).setData(data);

        // Check if the library, using the mocked precompile, returns the same szDecimals.
        assertEq(HyperTokenInfoPrecompile.szDecimals(uethIndex), originalSzDecimals, "Wrong szDecimals");
    }

    function testSpotPricePrecompile() public {
        uint32 uethUsdPairIndex = 151;
        // `cast call` the precompile to get the onchain data.
        bytes memory data = _ffiPrecompile(HyperSpotPricePrecompile.SPOT_PRICE_PRECOMPILE_ADDRESS, uethUsdPairIndex);
        // Store the spot price of the UETH/USD pair, as returned by the precompile.
        uint256 originalSpotPrice = abi.decode(data, (uint256));

        // Mock the precompile.
        vm.etch(HyperSpotPricePrecompile.SPOT_PRICE_PRECOMPILE_ADDRESS, address(new HypercorePrecompileMock()).code);
        // Set the onchain data to the mock.
        HypercorePrecompileMock(HyperSpotPricePrecompile.SPOT_PRICE_PRECOMPILE_ADDRESS).setData(data);

        // Check if the library, using the mocked precompile, returns the same spot price.
        assertEq(HyperSpotPricePrecompile.spotPrice(uethUsdPairIndex), originalSpotPrice, "Wrong spot price");
    }

    function _ffiPrecompile(address _precompile, uint32 index) internal returns (bytes memory) {
        bytes memory indexBytes = abi.encode(index);
        string[] memory inputs = new string[](6);
        inputs[0] = "cast";
        inputs[1] = "call";
        inputs[2] = string(abi.encodePacked("0x", _addressToHexString(_precompile)));
        inputs[3] = string(abi.encodePacked("0x", _bytesToHexString(indexBytes, 32)));
        inputs[4] = "--rpc-url";
        inputs[5] = "https://rpc.hyperliquid.xyz/evm";

        return vm.ffi(inputs);
    }

    function _addressToHexString(address _address) internal pure returns (string memory) {
        bytes20 _bytes = bytes20(_address);
        return (_bytesToHexString(abi.encode(_bytes), 20));
    }

    function _bytesToHexString(bytes memory _bytes, uint256 length) internal pure returns (string memory) {
        bytes memory answer = new bytes(2 * length);

        for (uint i = 0; i < length; i++) {
            answer[i * 2] = ALPHABET[uint8(_bytes[i] >> 4)];
            answer[i * 2 + 1] = ALPHABET[uint8(_bytes[i] & 0x0f)];
        }
        return string(answer);
    }
}
