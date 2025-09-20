pragma solidity ^0.8.13;

type Week is uint256;
using WeekLib for Week;    

library WeekLib {
    uint256 constant A_WEEK = 7 days;
    function getWeek(uint256 timestamp) internal pure returns (Week) {
        return Week.wrap(timestamp / A_WEEK);
    }
}