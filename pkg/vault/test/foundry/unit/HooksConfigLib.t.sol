// // SPDX-License-Identifier: GPL-3.0-or-later

// pragma solidity ^0.8.24;

// import "forge-std/Test.sol";

// import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
// import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

// import { HooksConfig, HooksConfigLib } from "@balancer-labs/v3-vault/contracts/lib/HooksConfigLib.sol";
// import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

// contract HooksConfigLibTest is Test {
//     using HooksConfigLib for HooksConfig;
//     using WordCodec for bytes32;

//     uint256 private constant MAX_UINT24_VALUE = uint256(type(uint24).max);
//     uint256 private constant MAX_UINT32_VALUE = uint256(type(uint32).max);
//     uint256 constant TOKEN_DECIMAL_DIFFS_BITLENGTH = 24;
//     uint8 constant DECIMAL_DIFF_BITLENGTH = 5;
//     uint256 constant TIMESTAMP_BITLENGTH = 32;

//     mapping(uint256 => bool) usedBits;

//     // 9 flags + 160 bit address = 169 total bits used.
//     uint256 private constant BITS_IN_USE = 169;

//     function testOffsets() public {
//         _checkBit(HooksConfigLib.DYNAMIC_SWAP_FEE_OFFSET);
//         _checkBit(HooksConfigLib.BEFORE_SWAP_OFFSET);
//         _checkBit(HooksConfigLib.AFTER_SWAP_OFFSET);
//         _checkBit(HooksConfigLib.BEFORE_ADD_LIQUIDITY_OFFSET);
//         _checkBit(HooksConfigLib.AFTER_ADD_LIQUIDITY_OFFSET);
//         _checkBit(HooksConfigLib.BEFORE_REMOVE_LIQUIDITY_OFFSET);
//         _checkBit(HooksConfigLib.AFTER_REMOVE_LIQUIDITY_OFFSET);
//         _checkBit(HooksConfigLib.BEFORE_INITIALIZE_OFFSET);
//         _checkBit(HooksConfigLib.AFTER_INITIALIZE_OFFSET);

//         _checkBits(HooksConfigLib.HOOKS_CONTRACT_OFFSET, 160); // Address has 160 bits
//     }

//     function testShouldCallComputeDynamicSwapFee() public {
//         assertTrue(
//             HooksConfigBits
//                 .wrap(bytes32(0).insertBool(true, HooksConfigLib.DYNAMIC_SWAP_FEE_OFFSET))
//                 .shouldCallComputeDynamicSwapFee(),
//             "shouldCallComputeDynamicSwapFee is false"
//         );
//     }

//     function testShouldCallBeforeSwap() public {
//         assertTrue(
//             HooksConfigBits.wrap(bytes32(0).insertBool(true, HooksConfigLib.BEFORE_SWAP_OFFSET)).shouldCallBeforeSwap(),
//             "shouldCallBeforeSwap is false"
//         );
//     }

//     function testShouldCallAfterSwap() public {
//         assertTrue(
//             HooksConfigBits.wrap(bytes32(0).insertBool(true, HooksConfigLib.AFTER_SWAP_OFFSET)).shouldCallAfterSwap(),
//             "shouldCallAfterSwap is false"
//         );
//     }

//     function testShouldCallBeforeAddLiquidity() public {
//         assertTrue(
//             HooksConfigBits
//                 .wrap(bytes32(0).insertBool(true, HooksConfigLib.BEFORE_ADD_LIQUIDITY_OFFSET))
//                 .shouldCallBeforeAddLiquidity(),
//             "shouldCallBeforeAddLiquidity is false"
//         );
//     }

//     function testShouldCallAfterAddLiquidity() public {
//         assertTrue(
//             HooksConfigBits
//                 .wrap(bytes32(0).insertBool(true, HooksConfigLib.AFTER_ADD_LIQUIDITY_OFFSET))
//                 .shouldCallAfterAddLiquidity(),
//             "shouldCallAfterAddLiquidity is false"
//         );
//     }

//     function testShouldCallBeforeRemoveLiquidity() public {
//         assertTrue(
//             HooksConfigBits
//                 .wrap(bytes32(0).insertBool(true, HooksConfigLib.BEFORE_REMOVE_LIQUIDITY_OFFSET))
//                 .shouldCallBeforeRemoveLiquidity(),
//             "shouldCallBeforeRemoveLiquidity is false"
//         );
//     }

//     function testShouldCallAfterRemoveLiquidity() public {
//         assertTrue(
//             HooksConfigBits
//                 .wrap(bytes32(0).insertBool(true, HooksConfigLib.AFTER_REMOVE_LIQUIDITY_OFFSET))
//                 .shouldCallAfterRemoveLiquidity(),
//             "shouldCallAfterRemoveLiquidity is false"
//         );
//     }

//     function testShouldCallBeforeInitialize() public {
//         assertTrue(
//             HooksConfigBits
//                 .wrap(bytes32(0).insertBool(true, HooksConfigLib.BEFORE_INITIALIZE_OFFSET))
//                 .shouldCallBeforeInitialize(),
//             "shouldCallBeforeInitialize is false"
//         );
//     }

//     function testShouldCallAfterInitialize() public {
//         assertTrue(
//             HooksConfigBits
//                 .wrap(bytes32(0).insertBool(true, HooksConfigLib.AFTER_INITIALIZE_OFFSET))
//                 .shouldCallAfterInitialize(),
//             "shouldCallAfterInitialize is false"
//         );
//     }

//     function testZeroConfigBytes() public {
//         HooksConfigBits configBits = HooksConfigBits.wrap(bytes32(0));

//         assertFalse(configBits.shouldCallComputeDynamicSwapFee(), "shouldCallComputeDynamicSwapFee is true");
//         assertFalse(configBits.shouldCallBeforeSwap(), "shouldCallBeforeSwap is true");
//         assertFalse(configBits.shouldCallAfterSwap(), "shouldCallAfterSwap is true");
//         assertFalse(configBits.shouldCallBeforeAddLiquidity(), "shouldCallBeforeAddLiquidity is true");
//         assertFalse(configBits.shouldCallAfterAddLiquidity(), "shouldCallAfterAddLiquidity is true");
//         assertFalse(configBits.shouldCallBeforeRemoveLiquidity(), "shouldCallBeforeRemoveLiquidity is true");
//         assertFalse(configBits.shouldCallAfterRemoveLiquidity(), "shouldCallAfterRemoveLiquidity is true");
//         assertFalse(configBits.shouldCallBeforeInitialize(), "shouldCallBeforeInitialize is true");
//         assertFalse(configBits.shouldCallAfterInitialize(), "shouldCallAfterInitialize is true");

//         assertEq(configBits.getHooksContract(), address(0), "hooks contract address isn't zero");
//     }

//     function test public {
//         assertEq(
//             HooksConfigBits
//                 .wrap(bytes32(0).insertAddress(address(0x123), HooksConfigLib.HOOKS_CONTRACT_OFFSET))
//                 .
//                 .hooksContract,
//             address(0x123),
//             "hooks contract mismatch (testToHooksConfig)"
//         );

//         // check hook flags
//         assertTrue(
//             HooksConfigBits
//                 .wrap(bytes32(0).insertBool(true, HooksConfigLib.BEFORE_INITIALIZE_OFFSET))
//                 .
//                 .shouldCallBeforeInitialize,
//             "shouldCallBeforeInitialize mismatch (testToHooksConfig)"
//         );

//         assertTrue(
//             HooksConfigBits
//                 .wrap(bytes32(0).insertBool(true, HooksConfigLib.AFTER_INITIALIZE_OFFSET))
//                 .
//                 .shouldCallAfterInitialize,
//             "shouldCallAfterInitialize mismatch (testToHooksConfig)"
//         );

//         assertTrue(
//             HooksConfigBits
//                 .wrap(bytes32(0).insertBool(true, HooksConfigLib.BEFORE_ADD_LIQUIDITY_OFFSET))
//                 .
//                 .shouldCallBeforeAddLiquidity,
//             "shouldCallBeforeAddLiquidity mismatch (testToHooksConfig)"
//         );

//         assertTrue(
//             HooksConfigBits
//                 .wrap(bytes32(0).insertBool(true, HooksConfigLib.AFTER_ADD_LIQUIDITY_OFFSET))
//                 .
//                 .shouldCallAfterAddLiquidity,
//             "shouldCallAfterAddLiquidity mismatch (testToHooksConfig)"
//         );

//         assertTrue(
//             HooksConfigBits
//                 .wrap(bytes32(0).insertBool(true, HooksConfigLib.BEFORE_REMOVE_LIQUIDITY_OFFSET))
//                 .
//                 .shouldCallBeforeRemoveLiquidity,
//             "shouldCallBeforeRemoveLiquidity mismatch (testToHooksConfig)"
//         );

//         assertTrue(
//             HooksConfigBits
//                 .wrap(bytes32(0).insertBool(true, HooksConfigLib.AFTER_REMOVE_LIQUIDITY_OFFSET))
//                 .
//                 .shouldCallAfterRemoveLiquidity,
//             "shouldCallAfterRemoveLiquidity mismatch (testToHooksConfig)"
//         );

//         assertTrue(
//             HooksConfigBits
//                 .wrap(bytes32(0).insertBool(true, HooksConfigLib.DYNAMIC_SWAP_FEE_OFFSET))
//                 .
//                 .shouldCallComputeDynamicSwapFee,
//             "shouldCallComputeDynamicSwapFee mismatch (testToHooksConfig)"
//         );

//         assertTrue(
//             HooksConfigBits
//                 .wrap(bytes32(0).insertBool(true, HooksConfigLib.BEFORE_SWAP_OFFSET))
//                 .
//                 .shouldCallBeforeSwap,
//             "shouldCallBeforeSwap mismatch (testToHooksConfig)"
//         );

//         assertTrue(
//             HooksConfigBits
//                 .wrap(bytes32(0).insertBool(true, HooksConfigLib.AFTER_SWAP_OFFSET))
//                 .
//                 .shouldCallAfterSwap,
//             "shouldCallAfterSwap mismatch (testToHooksConfig)"
//         );
//     }

//     function testFromHooksConfig() public {
//         HooksConfig memory config = _createEmptyConfig();

//         // check hooks flags
//         config = _createEmptyConfig();
//         config.shouldCallBeforeInitialize = true;
//         assertEq(
//             HooksConfigBits.unwrap(HooksConfigLib.fromHooksConfig(config)),
//             bytes32(0).insertBool(true, HooksConfigLib.BEFORE_INITIALIZE_OFFSET),
//             "shouldCallBeforeInitialize mismatch (testFromHooksConfig)"
//         );

//         config = _createEmptyConfig();
//         config.shouldCallAfterInitialize = true;
//         assertEq(
//             HooksConfigBits.unwrap(HooksConfigLib.fromHooksConfig(config)),
//             bytes32(0).insertBool(true, HooksConfigLib.AFTER_INITIALIZE_OFFSET),
//             "shouldCallAfterInitialize mismatch (testFromHooksConfig)"
//         );

//         config = _createEmptyConfig();
//         config.shouldCallBeforeAddLiquidity = true;
//         assertEq(
//             HooksConfigBits.unwrap(HooksConfigLib.fromHooksConfig(config)),
//             bytes32(0).insertBool(true, HooksConfigLib.BEFORE_ADD_LIQUIDITY_OFFSET),
//             "shouldCallBeforeAddLiquidity mismatch (testFromHooksConfig)"
//         );

//         config = _createEmptyConfig();
//         config.shouldCallAfterAddLiquidity = true;
//         assertEq(
//             HooksConfigBits.unwrap(HooksConfigLib.fromHooksConfig(config)),
//             bytes32(0).insertBool(true, HooksConfigLib.AFTER_ADD_LIQUIDITY_OFFSET),
//             "shouldCallAfterAddLiquidity mismatch (testFromHooksConfig)"
//         );

//         config = _createEmptyConfig();
//         config.shouldCallBeforeRemoveLiquidity = true;
//         assertEq(
//             HooksConfigBits.unwrap(HooksConfigLib.fromHooksConfig(config)),
//             bytes32(0).insertBool(true, HooksConfigLib.BEFORE_REMOVE_LIQUIDITY_OFFSET),
//             "shouldCallBeforeRemoveLiquidity mismatch (testFromHooksConfig)"
//         );

//         config = _createEmptyConfig();
//         config.shouldCallAfterRemoveLiquidity = true;
//         assertEq(
//             HooksConfigBits.unwrap(HooksConfigLib.fromHooksConfig(config)),
//             bytes32(0).insertBool(true, HooksConfigLib.AFTER_REMOVE_LIQUIDITY_OFFSET),
//             "shouldCallAfterRemoveLiquidity mismatch (testFromHooksConfig)"
//         );

//         config = _createEmptyConfig();
//         config.shouldCallComputeDynamicSwapFee = true;
//         assertEq(
//             HooksConfigBits.unwrap(HooksConfigLib.fromHooksConfig(config)),
//             bytes32(0).insertBool(true, HooksConfigLib.DYNAMIC_SWAP_FEE_OFFSET),
//             "shouldCallComputeDynamicSwapFee mismatch (testFromHooksConfig)"
//         );

//         config = _createEmptyConfig();
//         config.shouldCallBeforeSwap = true;
//         assertEq(
//             HooksConfigBits.unwrap(HooksConfigLib.fromHooksConfig(config)),
//             bytes32(0).insertBool(true, HooksConfigLib.BEFORE_SWAP_OFFSET),
//             "shouldCallBeforeSwap mismatch (testFromHooksConfig)"
//         );

//         config = _createEmptyConfig();
//         config.shouldCallAfterSwap = true;
//         assertEq(
//             HooksConfigBits.unwrap(HooksConfigLib.fromHooksConfig(config)),
//             bytes32(0).insertBool(true, HooksConfigLib.AFTER_SWAP_OFFSET),
//             "shouldCallAfterSwap mismatch (testFromHooksConfig)"
//         );

//         // check hooks contract
//         config = _createEmptyConfig();
//         config.hooksContract = address(0x123);
//         assertEq(
//             HooksConfigBits.unwrap(HooksConfigLib.fromHooksConfig(config)),
//             bytes32(0).insertAddress(address(0x123), HooksConfigLib.HOOKS_CONTRACT_OFFSET),
//             "hooks contract mismatch (testFromHooksConfig)"
//         );
//     }

//     function testToHooksConfigWithZeroBytes() public {
//         HooksConfig memory zeroHooksConfig;

//         assertEq(
//             keccak256(abi.encode(HooksConfigBits.wrap(bytes32(0)).)),
//             keccak256(abi.encode(zeroHooksConfig)),
//             "poolConfig isn't zeroHooksConfig"
//         );
//     }

//     function testToAndFromConfigBits__Fuzz(uint256 rawConfigInt) public {
//         rawConfigInt = bound(rawConfigInt, 0, uint256(1 << BITS_IN_USE) - 1);
//         bytes32 rawConfig = bytes32(rawConfigInt);
//         HooksConfig memory config = HooksConfigLib.toHooksConfig(HooksConfigBits.wrap(rawConfig));
//         bytes32 configBytes32 = HooksConfigBits.unwrap(HooksConfigLib.fromHooksConfig(config));

//         assertEq(rawConfig, configBytes32);
//     }

//     function testUnusedConfigBits() public {
//         bytes32 unusedBits = bytes32(uint256(type(uint256).max << (BITS_IN_USE)));

//         HooksConfig memory config = HooksConfigLib.toHooksConfig(HooksConfigBits.wrap(unusedBits));
//         bytes32 configBytes32 = HooksConfigBits.unwrap(HooksConfigLib.fromHooksConfig(config));

//         assertEq(bytes32(0), configBytes32);
//     }

//    function _createEmptyConfig() private pure returns (HooksConfig memory config) {
//        return config;
//    }

//     function _checkBits(uint256 startBit, uint256 size) private {
//         uint256 endBit = startBit + size;
//         for (uint256 i = startBit; i < endBit; i++) {
//             _checkBit(i);
//         }
//     }

//     function _checkBit(uint256 bitNumber) private {
//         assertEq(usedBits[bitNumber], false, "Bit already used");
//         usedBits[bitNumber] = true;
//     }
// }
