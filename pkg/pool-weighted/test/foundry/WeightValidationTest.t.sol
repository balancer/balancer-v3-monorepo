// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/lib/WeightValidation.sol";

// Wrapper contract to expose library functions
contract WeightValidationWrapper {
    function validateWeights(uint256[] memory normalizedWeights, uint256 numTokens) public pure {
        WeightValidation.validateWeights(normalizedWeights, numTokens);
    }

    function validateTwoWeights(uint256 normalizedWeight0, uint256 normalizedWeight1) public pure {
        WeightValidation.validateTwoWeights(normalizedWeight0, normalizedWeight1);
    }
}

contract WeightValidationTest is Test {
    WeightValidationWrapper private wrapper;
    uint256 private constant FP_ONE = 1e18; // FixedPoint.ONE
    uint256 private constant MIN_WEIGHT = 1e16; // 1%

    function setUp() public {
        wrapper = new WeightValidationWrapper();
    }

    function testValidateWeightsValidRangeMultipleTokens() public view {
        for (uint256 numTokens = 2; numTokens <= 8; numTokens++) {
            uint256[] memory weights = new uint256[](numTokens);
            uint256 remainingWeight = FP_ONE;
            
            for (uint256 i = 0; i < numTokens - 1; i++) {
                uint256 weight = (remainingWeight / (numTokens - i)) + 1e16; // Ensure it's above MIN_WEIGHT
                weights[i] = weight;
                remainingWeight -= weight;
            }
            weights[numTokens - 1] = remainingWeight;
            
            wrapper.validateWeights(weights, numTokens);
        }
    }

    function testValidateWeightsEdgeCases() public view {
        // Test with all weights at minimum except one
        uint256[] memory weights = new uint256[](5);
        for (uint256 i = 0; i < 4; i++) {
            weights[i] = MIN_WEIGHT;
        }
        weights[4] = FP_ONE - (MIN_WEIGHT * 4);
        wrapper.validateWeights(weights, 5);

        // Test with two weights splitting the total
        uint256[] memory twoWeights = new uint256[](2);
        twoWeights[0] = FP_ONE / 2;
        twoWeights[1] = FP_ONE / 2;
        wrapper.validateWeights(twoWeights, 2);
    }

    function testValidateWeightsInvalidSum() public {
        uint256[] memory weights = new uint256[](3);
        weights[0] = 0.3e18;
        weights[1] = 0.3e18;
        weights[2] = 0.3e18;
        vm.expectRevert(WeightValidation.NormalizedWeightInvariant.selector);
        wrapper.validateWeights(weights, 3);

        // Test with sum slightly above FP_ONE
        weights[2] = 0.400000000000000001e18;
        vm.expectRevert(WeightValidation.NormalizedWeightInvariant.selector);
        wrapper.validateWeights(weights, 3);
    }

    function testValidateWeightsBelowMinWeight() public {
        uint256[] memory weights = new uint256[](3);
        weights[0] = MIN_WEIGHT - 1;
        weights[1] = (FP_ONE - MIN_WEIGHT + 1) / 2;
        weights[2] = (FP_ONE - MIN_WEIGHT + 1) / 2;
        vm.expectRevert(WeightValidation.MinWeight.selector);
        wrapper.validateWeights(weights, 3);
    }

    function testValidateTwoWeightsValidRange() public view {
        for (uint256 i = MIN_WEIGHT; i <= FP_ONE - MIN_WEIGHT; i += 1e16) {
            wrapper.validateTwoWeights(i, FP_ONE - i);
        }
    }

    function testValidateTwoWeightsInvalidSum() public {
        vm.expectRevert(WeightValidation.NormalizedWeightInvariant.selector);
        wrapper.validateTwoWeights(0.5e18, 0.500000000000000001e18);

        vm.expectRevert(WeightValidation.NormalizedWeightInvariant.selector);
        wrapper.validateTwoWeights(0.5e18, 0.499999999999999999e18);
    }

    function testValidateTwoWeightsBelowMinWeight() public {
        vm.expectRevert(WeightValidation.MinWeight.selector);
        wrapper.validateTwoWeights(MIN_WEIGHT - 1, FP_ONE - MIN_WEIGHT + 1);

        vm.expectRevert(WeightValidation.MinWeight.selector);
        wrapper.validateTwoWeights(FP_ONE - MIN_WEIGHT + 1, MIN_WEIGHT - 1);
    }

    function testValidateTwoWeightsEdgeCases() public view {
        wrapper.validateTwoWeights(MIN_WEIGHT, FP_ONE - MIN_WEIGHT);
        wrapper.validateTwoWeights(FP_ONE - MIN_WEIGHT, MIN_WEIGHT);
        wrapper.validateTwoWeights(FP_ONE / 2, FP_ONE / 2);
    }
}