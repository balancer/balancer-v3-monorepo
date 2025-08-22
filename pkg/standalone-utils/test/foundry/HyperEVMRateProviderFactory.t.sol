// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IVersion.sol";
import {
    IHyperEVMRateProviderFactory
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IHyperEVMRateProviderFactory.sol";
import {
    IHyperEVMRateProvider
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IHyperEVMRateProvider.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { HyperEVMRateProviderFactory } from "../../contracts/HyperEVMRateProviderFactory.sol";
import { HyperTokenInfoPrecompile } from "../../contracts/utils/HyperTokenInfoPrecompile.sol";
import { HypercorePrecompileMock } from "./utils/HypercorePrecompileMock.sol";

contract HyperEVMRateProviderFactoryTest is BaseVaultTest {
    string constant RATE_PROVIDER_FACTORY_VERSION = "Factory v1";
    uint256 constant RATE_PROVIDER_VERSION = 1;

    uint32 private constant _UETH_TOKEN_INDEX = 221;
    uint32 private constant _UETH_PAIR_INDEX = 151;

    IHyperEVMRateProviderFactory internal _factory;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _factory = _createRateProviderFactory();

        authorizer.grantRole(
            IAuthentication(address(_factory)).getActionId(IHyperEVMRateProviderFactory.disable.selector),
            admin
        );

        // Setup TokenInfo precompile (used on rate provider constructor).
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
                    szDecimals: 4,
                    weiDecimals: 9,
                    evmExtraWeiDecimals: 9
                })
            )
        );
    }

    function testRateProviderFactoryVersion() public view {
        assertEq(
            IVersion(address(_factory)).version(),
            RATE_PROVIDER_FACTORY_VERSION,
            "Wrong rate provider factory version"
        );
    }

    function testRateProviderVersion() public view {
        assertEq(_factory.getRateProviderVersion(), RATE_PROVIDER_VERSION, "Wrong rate provider version");
    }

    function testCreateRateProvider() external {
        IHyperEVMRateProvider rateProvider;

        uint256 snapId = vm.snapshot();
        rateProvider = _factory.create(_UETH_TOKEN_INDEX, _UETH_PAIR_INDEX);
        address rateProviderAddress = address(rateProvider);
        vm.revertTo(snapId);

        vm.expectEmit();
        emit IHyperEVMRateProviderFactory.RateProviderCreated(_UETH_TOKEN_INDEX, _UETH_PAIR_INDEX, rateProviderAddress);
        rateProvider = _factory.create(_UETH_TOKEN_INDEX, _UETH_PAIR_INDEX);

        assertEq(
            address(rateProvider),
            address(_factory.getRateProvider(_UETH_TOKEN_INDEX, _UETH_PAIR_INDEX)),
            "Rate provider address mismatch"
        );
        assertTrue(_factory.isRateProviderFromFactory(rateProvider), "Rate provider should be from factory");
        assertEq(rateProvider.getTokenIndex(), _UETH_TOKEN_INDEX, "Wrong token index");
        assertEq(rateProvider.getPairIndex(), _UETH_PAIR_INDEX, "Wrong pair index");
    }

    function testGetNonExistentRateProvider() external view {
        assertEq(address(_factory.getRateProvider(uint32(1), uint32(2))), address(0), "Rate provider address mismatch");
    }

    function testCreateRateProviderDifferentTokenAndPair() external {
        IHyperEVMRateProvider rateProvider = _factory.create(uint32(1), uint32(2));

        assertEq(
            address(rateProvider),
            address(_factory.getRateProvider(uint32(1), uint32(2))),
            "Rate provider address mismatch"
        );
        assertTrue(_factory.isRateProviderFromFactory(rateProvider), "Rate provider should be from factory");

        IHyperEVMRateProvider rateProvider2 = _factory.create(uint32(2), uint32(1));

        assertEq(
            address(rateProvider2),
            address(_factory.getRateProvider(uint32(2), uint32(1))),
            "Rate provider address mismatch"
        );
        assertTrue(_factory.isRateProviderFromFactory(rateProvider2), "Rate provider should be from factory");
    }

    function testCreateRateProviderRevertsWhenRateProviderAlreadyExists() external {
        IHyperEVMRateProvider rateProvider = _factory.create(_UETH_TOKEN_INDEX, _UETH_PAIR_INDEX);

        // Since there already is an rate provider for the pool in the factory, reverts with the correct parameters.
        vm.expectRevert(
            abi.encodeWithSelector(
                IHyperEVMRateProviderFactory.RateProviderAlreadyExists.selector,
                _UETH_TOKEN_INDEX,
                _UETH_PAIR_INDEX,
                address(rateProvider)
            )
        );
        _factory.create(_UETH_TOKEN_INDEX, _UETH_PAIR_INDEX);
    }

    function testDisable() public {
        vm.prank(admin);
        _factory.disable();

        vm.expectRevert(IHyperEVMRateProviderFactory.RateProviderFactoryIsDisabled.selector);
        _factory.create(_UETH_TOKEN_INDEX, _UETH_PAIR_INDEX);

        // Revert the second time
        vm.prank(admin);
        vm.expectRevert(IHyperEVMRateProviderFactory.RateProviderFactoryIsDisabled.selector);
        _factory.disable();
    }

    function testDisableIsAuthenticated() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _factory.disable();
    }

    function _createRateProviderFactory() internal returns (IHyperEVMRateProviderFactory) {
        return new HyperEVMRateProviderFactory(vault, RATE_PROVIDER_FACTORY_VERSION, RATE_PROVIDER_VERSION);
    }
}
