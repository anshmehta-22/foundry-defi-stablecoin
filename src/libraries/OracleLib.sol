//SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
 * @title OracleLib 
 * @author Ansh Mehta
 * @notice: This library is used to check the chainlink oracle for stable data.
 * If a price is stale, the function will revert, and render the DSCEngine unusable - this is by design.
 * We want the DSCEngine to freeze if prices become stale.
 *
 * So if the chainlink network explodes and you have a lot of money locked in the protocol -> not so good.
 */
library OracleLib{
    error OracleLib__StalePrice();

    /*
    TIMEOUT is in hours. 
    Tip: "> hours" is a keyword in solidity that is effectively *60*60 seconds. 
    3 hours == 3 * 60 * 60 == 10800 seconds
    */
    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed) public view returns(uint80, int256, uint256, uint256, uint80) {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
            ) = priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) {                           
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);

    }
}