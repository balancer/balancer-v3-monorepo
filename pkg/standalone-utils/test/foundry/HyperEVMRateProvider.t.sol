// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { HyperTokenInfoPrecompile } from "../../contracts/utils/HyperTokenInfoPrecompile.sol";
import { HyperSpotPricePrecompile } from "../../contracts/utils/HyperSpotPricePrecompile.sol";
import { HyperEVMRateProvider } from "../../contracts/HyperEVMRateProvider.sol";
import { HypercorePrecompileMock } from "./utils/HypercorePrecompileMock.sol";

contract HyperEVMRateProviderTest is Test {
    HyperEVMRateProvider private hyperEVMRateProvider;

    uint256 private constant _UETH_USD_RATE = 43848000;
    uint8 private constant _UETH_SZ_DECIMALS = 4;

    function setUp() public {
        vm.etch(HyperSpotPricePrecompile.SPOT_PRICE_PRECOMPILE_ADDRESS, address(new HypercorePrecompileMock()).code);
        vm.etch(HyperTokenInfoPrecompile.TOKEN_INFO_PRECOMPILE_ADDRESS, address(new HypercorePrecompileMock()).code);

        // Data from `cast call PRECOMPILE_ADDRESS TOKEN_INDEX --rpc-url $RPC`. UETH data.
        uint64[] memory spots = new uint64[](1);
        spots[0] = 151;
        HypercorePrecompileMock(HyperTokenInfoPrecompile.TOKEN_INFO_PRECOMPILE_ADDRESS).setData(
            abi.encode(
                HyperTokenInfoPrecompile.HyperTokenInfo({
                    name: "UETH",
                    spots: spots,
                    deployerTradingFeeShare: 100000,
                    deployer: address(0xF036a5261406a394bd63Eb4dF49C464634a66155),
                    evmContract: address(0xBe6727B535545C67d5cAa73dEa54865B92CF7907),
                    szDecimals: _UETH_SZ_DECIMALS,
                    weiDecimals: 9,
                    evmExtraWeiDecimals: 9
                })
            )
        );

        // Data from `cast call PRECOMPILE_ADDRESS PAIR_INDEX --rpc-url $RPC`. UETH/USD data.
        HypercorePrecompileMock(HyperSpotPricePrecompile.SPOT_PRICE_PRECOMPILE_ADDRESS).setData(
            abi.encode(_UETH_USD_RATE)
        );

        // Deploy the rate provider.
        hyperEVMRateProvider = new HyperEVMRateProvider(221, 151);
    }

    function testGetRateHyperEVM() public view {
        assertEq(hyperEVMRateProvider.getRate(), (_UETH_USD_RATE * 1e18) / 10 ** (8 - _UETH_SZ_DECIMALS), "Wrong rate");
    }
}
