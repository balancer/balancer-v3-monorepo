// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFeeCollector {
    enum Epoch {
        SLEEP,
        COLLECT,
        EXCHANGE,
        FORWARD
    }

    struct Transfer {
        IERC20 coin;
        address to;
        // Used 2^256-1 for the whole balance
        uint256 amount;
    }

    /**
     * @notice Calculate keeper's fee
     * @return Fee with base 10^18
     */
    function fee() external view returns (uint256);

    /**
     * @notice Calculate keeper's fee
     * @param epoch Epoch to count fee for
     * @return Fee with base 10^18
     */
    function fee(uint256 epoch) external view returns (uint256);

    /**
     * @notice Calculate keeper's fee
     * @param epoch Epoch to count fee for
     * @param timestamp Timestamp of collection
     * @return Fee with base 10^18
     */
    function fee(uint256 epoch, uint256 timestamp) external view returns (uint256);

    /**
     * @notice Get target coin swapped into
     * @return Coin swapped into
     */
    function target() external view returns (IERC20);

    /**
     * @notice Get owner address
     * @return Owner address
     */
    function owner() external view returns (address);

    /**
     * @notice Get emergency owner address.  Can kill the contract.
     * @return Emergency owner address
     */
    function emergency_owner() external view returns (address);

    /**
     * @notice Get time frame of certain epoch. Timestamp anchor to current block.timestamp.
     * @param epoch Epoch number
     * @return start Start time frame boundaries
     * @return end End time frame boundaries
     *
     * @dev The start and end timestamps must remain fixed within an epoch.
     * If the timestamp changes frequently, the order cannot be executed.
     */
    function epoch_time_frame(uint256 epoch) external view returns (uint256 start, uint256 end);

    /**
     * @notice Get time frame of certain epoch
     * @param epoch Epoch number
     * @param timestamp Timestamp to anchor to
     * @return start Start time frame boundaries
     * @return end End time frame boundaries
     *
     * @dev The start and end timestamps must remain fixed within an epoch.
     * If the timestamp changes frequently, the order cannot be executed.
     */
    function epoch_time_frame(uint256 epoch, uint256 timestamp) external view returns (uint256, uint256);

    /**
     * @notice Check whether coins are allowed to be exchanged
     * @param coins Coins to exchange
     * @return Boolean value if coins are allowed to be exchanged
     */
    function can_exchange(IERC20[] memory coins) external view returns (bool);

    /**
     * @notice Transfer coins to target addresses
     * @dev No approvals so can change burner easily
     * @param transfers Transfers to apply
     */
    function transfer(Transfer[] memory transfers) external;
}
