// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ILPOracleBase.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

/**
 * @notice Base contract for pool oracles.
 * @dev The most important function of this contract is `calculateTVL`. This function must be implemented by each
 * oracle that inherits this contract, and it must return the total value locked (TVL) of the pool. The rest of
 * this contract are standard functions that makes the oracle compatible with Chainlink's AggregatorV3Interface.
 */
abstract contract LPOracleBase is ILPOracleBase, AggregatorV3Interface {
    using FixedPoint for uint256;
    using SafeCast for *;

    uint256 internal constant _WAD_DECIMALS = 18;

    IBasePool public immutable pool;

    IVault internal immutable _vault;
    uint256 internal immutable _version;
    uint256 internal immutable _totalTokens;
    string internal _description;

    AggregatorV3Interface internal immutable _feedToken0;
    AggregatorV3Interface internal immutable _feedToken1;
    AggregatorV3Interface internal immutable _feedToken2;
    AggregatorV3Interface internal immutable _feedToken3;
    AggregatorV3Interface internal immutable _feedToken4;
    AggregatorV3Interface internal immutable _feedToken5;
    AggregatorV3Interface internal immutable _feedToken6;
    AggregatorV3Interface internal immutable _feedToken7;

    uint256 internal immutable _feedToken0DecimalScalingFactor;
    uint256 internal immutable _feedToken1DecimalScalingFactor;
    uint256 internal immutable _feedToken2DecimalScalingFactor;
    uint256 internal immutable _feedToken3DecimalScalingFactor;
    uint256 internal immutable _feedToken4DecimalScalingFactor;
    uint256 internal immutable _feedToken5DecimalScalingFactor;
    uint256 internal immutable _feedToken6DecimalScalingFactor;
    uint256 internal immutable _feedToken7DecimalScalingFactor;

    constructor(IVault vault_, IBasePool pool_, AggregatorV3Interface[] memory feeds, uint256 version_) {
        _version = version_;
        _vault = vault_;
        pool = pool_;

        IERC20[] memory tokens = vault_.getPoolTokens(address(pool_));
        uint totalTokens = tokens.length;

        _totalTokens = totalTokens;
        _description = string.concat(IERC20Metadata(address(pool)).symbol(), "/USD");

        InputHelpers.ensureInputLengthMatch(totalTokens, feeds.length);

        // prettier-ignore
        {
            _feedToken0 = feeds[0];
            _feedToken0DecimalScalingFactor = _computeFeedTokenDecimalScalingFactor(feeds[0]);

            _feedToken1 = feeds[1];
            _feedToken1DecimalScalingFactor = _computeFeedTokenDecimalScalingFactor(feeds[1]);
        
            if (totalTokens > 2) { 
                _feedToken2 = feeds[2];
                _feedToken2DecimalScalingFactor = _computeFeedTokenDecimalScalingFactor(feeds[2]);
            }
            if (totalTokens > 3) { 
                _feedToken3 = feeds[3];
                _feedToken3DecimalScalingFactor = _computeFeedTokenDecimalScalingFactor(feeds[3]);
            }
            if (totalTokens > 4) {
                _feedToken4 = feeds[4];
                _feedToken4DecimalScalingFactor = _computeFeedTokenDecimalScalingFactor(feeds[4]);
            }
            if (totalTokens > 5) {
                _feedToken5 = feeds[5];
                _feedToken5DecimalScalingFactor = _computeFeedTokenDecimalScalingFactor(feeds[5]);
            }
            if (totalTokens > 6) {
                _feedToken6 = feeds[6];
                _feedToken6DecimalScalingFactor = _computeFeedTokenDecimalScalingFactor(feeds[6]);
            }
            if (totalTokens > 7) {
                _feedToken7 = feeds[7];
                _feedToken7DecimalScalingFactor = _computeFeedTokenDecimalScalingFactor(feeds[7]);
            }
        }
    }

    /**
     * @notice Get the version of the oracle.
     * @dev Declared in AggregatorV3Interface.
     * @return version The numerical version number
     */
    function version() external view returns (uint256) {
        return _version;
    }

    /**
     * @notice Get the number of decimals present in the response value.
     * @dev Declared in AggregatorV3Interface. This is hard-coded to 18 decimals.
     * @return decimals The number of decimals
     */
    function decimals() external pure returns (uint8) {
        return uint8(_WAD_DECIMALS);
    }

    /**
     * @notice Get the description of the underlying aggregator that the proxy points to.
     * @dev Declared in AggregatorV3Interface.
     * @return description The description as a string
     */
    function description() external view returns (string memory) {
        return _description;
    }

    /**
     * @notice Get data about a specific round, using the roundId.
     * @dev Declared in AggregatorV3Interface. This is unused, and always returns all zeros.
     * @return roundId The round ID
     * @return answer The answer for this round
     * @return startedAt Timestamp when the round started
     * @return updatedAt Timestamp when the round was updated
     * @return answeredInRound [Deprecated] - Previously used when answers could take multiple rounds to be computed
     */
    function getRoundData(
        uint80 /* _roundId */
    )
        external
        pure
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, 0, 0, 0, 0);
    }

    /**
     * @notice Get the data from the latest round.
     * @dev Declared in AggregatorV3Interface.
     * @return roundId The round ID
     * @return answer The answer for this round
     * @return startedAt Timestamp when the round started
     * @return updatedAt Timestamp when the round was updated
     * @return answeredInRound [Deprecated] - Previously used when answers could take multiple rounds to be computed
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (int256[] memory prices, uint256 _updatedAt) = getFeedData();

        uint256 tvl = calculateTVL(prices);
        uint256 totalSupply = _vault.totalSupply(address(pool));

        uint256 lpPrice = tvl.divUp(totalSupply);

        return (0, lpPrice.toInt256(), 0, _updatedAt, 0);
    }

    /// @inheritdoc ILPOracleBase
    function calculateTVL(int256[] memory) public view virtual returns (uint256);

    /// @inheritdoc ILPOracleBase
    function getFeedData() public view returns (int256[] memory prices, uint256 updatedAt) {
        uint256 totalTokens = _totalTokens;
        AggregatorV3Interface[] memory feeds = _getFeeds(totalTokens);
        uint256[] memory feedDecimalScalingFactors = _getFeedTokenDecimalScalingFactors(totalTokens);

        prices = new int256[](totalTokens);

        updatedAt = type(uint256).max;
        for (uint256 i = 0; i < totalTokens; i++) {
            (, int256 answer, , uint256 feedUpdatedAt, ) = feeds[i].latestRoundData();
            prices[i] = answer * feedDecimalScalingFactors[i].toInt256();

            updatedAt = updatedAt < feedUpdatedAt ? updatedAt : feedUpdatedAt;
        }
    }

    /// @inheritdoc ILPOracleBase
    function getFeeds() external view returns (AggregatorV3Interface[] memory) {
        return _getFeeds(_totalTokens);
    }

    /// @inheritdoc ILPOracleBase
    function getFeedTokenDecimalScalingFactors() external view returns (uint256[] memory) {
        return _getFeedTokenDecimalScalingFactors(_totalTokens);
    }

    /// @inheritdoc ILPOracleBase
    function getPoolTokens() external view returns (IERC20[] memory) {
        return _vault.getPoolTokens(address(pool));
    }

    function _computeFeedTokenDecimalScalingFactor(AggregatorV3Interface feed) internal view returns (uint256) {
        uint256 feedDecimals = feed.decimals();

        if (feedDecimals > _WAD_DECIMALS) {
            revert UnsupportedDecimals();
        }

        return 10 ** (_WAD_DECIMALS - feedDecimals);
    }

    function _getFeeds(uint256 totalTokens) internal view virtual returns (AggregatorV3Interface[] memory) {
        AggregatorV3Interface[] memory feeds = new AggregatorV3Interface[](totalTokens);

        // prettier-ignore
        {
            feeds[0] = _feedToken0;
            feeds[1] = _feedToken1;
            if (totalTokens > 2) { feeds[2] = _feedToken2; } else { return feeds; }
            if (totalTokens > 3) { feeds[3] = _feedToken3; } else { return feeds; }
            if (totalTokens > 4) { feeds[4] = _feedToken4; } else { return feeds; }
            if (totalTokens > 5) { feeds[5] = _feedToken5; } else { return feeds; }
            if (totalTokens > 6) { feeds[6] = _feedToken6; } else { return feeds; }
            if (totalTokens > 7) { feeds[7] = _feedToken7; }
        }

        return feeds;
    }

    function _getFeedTokenDecimalScalingFactors(uint256 totalTokens) internal view returns (uint256[] memory) {
        uint256[] memory feedTokenDecimalScalingFactors = new uint256[](totalTokens);

        // prettier-ignore
        {
            feedTokenDecimalScalingFactors[0] = _feedToken0DecimalScalingFactor;
            feedTokenDecimalScalingFactors[1] = _feedToken1DecimalScalingFactor;
            if (totalTokens > 2) { feedTokenDecimalScalingFactors[2] = _feedToken2DecimalScalingFactor; } 
                else { return feedTokenDecimalScalingFactors; }
            if (totalTokens > 3) { feedTokenDecimalScalingFactors[3] = _feedToken3DecimalScalingFactor; }
                else { return feedTokenDecimalScalingFactors; }
            if (totalTokens > 4) { feedTokenDecimalScalingFactors[4] = _feedToken4DecimalScalingFactor; }
                else { return feedTokenDecimalScalingFactors; }
            if (totalTokens > 5) { feedTokenDecimalScalingFactors[5] = _feedToken5DecimalScalingFactor; } 
                else { return feedTokenDecimalScalingFactors; }
            if (totalTokens > 6) { feedTokenDecimalScalingFactors[6] = _feedToken6DecimalScalingFactor; } 
                else { return feedTokenDecimalScalingFactors; }
            if (totalTokens > 7) { feedTokenDecimalScalingFactors[7] = _feedToken7DecimalScalingFactor; }
        }

        return feedTokenDecimalScalingFactors;
    }
}
