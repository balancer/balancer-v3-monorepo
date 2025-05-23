// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Copy from:
// https://github.com/smartcontractkit/chainlink/blob/contracts-v1.3.0/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol
// Docs: https://docs.chain.link/data-feeds/api-reference#getrounddata

interface IChainlinkAggregatorV3 {
    /// @notice Get the number of decimals present in the response value.
    function decimals() external view returns (uint8);

    /// @notice Get the description of the underlying aggregator that the proxy points to.
    function description() external view returns (string memory);

    /// @notice The version representing the type of aggregator the proxy points to.
    function version() external view returns (uint256);

    /**
     * @notice Get data about a specific round, using the roundId.
     * @param _roundId The round ID
     * @return roundId The round ID
     * @return answer The answer for this round
     * @return startedAt Timestamp of when the round started
     * @return updatedAt Timestamp of when the round was updated
     * @return answeredInRound [Deprecated] - Previously used when answers could take multiple rounds to be computed
     */
    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /**
     * @notice Get the data from the latest round.
     * @return roundId The round ID
     * @return answer The data that this specific feed provides.
     * Depending on the feed you selected, this answer provides asset prices, reserves, and other types of data.
     *
     * @return startedAt Timestamp of when the round started
     * @return updatedAt Timestamp of when the round was updated
     * @return answeredInRound [Deprecated] - Previously used when answers could take multiple rounds to be computed
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
