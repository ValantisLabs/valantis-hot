// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { AggregatorV3Interface } from '../../src/vendor/chainlink/AggregatorV3Interface.sol';

contract MockChainlinkOracle is AggregatorV3Interface {
    /************************************************
     *  MOCK CHAINLINK ORACLE
     ***********************************************/
    uint8 private _decimals;
    string private _description = 'MOCK CHAINLINK ORACLE';
    uint256 private _version = 1;
    uint80 private latestRoundId;

    struct Round {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    mapping(uint80 => Round) roundData;

    constructor(uint8 decimalsValue) {
        _decimals = decimalsValue;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external view returns (string memory) {
        return _description;
    }

    function version() external view returns (uint256) {
        return _version;
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (
            roundData[_roundId].roundId,
            roundData[_roundId].answer,
            roundData[_roundId].startedAt,
            roundData[_roundId].updatedAt,
            roundData[_roundId].answeredInRound
        );
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (
            roundData[latestRoundId].roundId,
            roundData[latestRoundId].answer,
            roundData[latestRoundId].startedAt,
            roundData[latestRoundId].updatedAt,
            roundData[latestRoundId].answeredInRound
        );
    }

    function setRoundData(Round memory _roundData) public {
        if (_roundData.roundId > latestRoundId) {
            latestRoundId = _roundData.roundId;
        }
        roundData[_roundData.roundId] = _roundData;
    }

    function setLatestRoundData(Round memory _roundData) public {
        latestRoundId = _roundData.roundId;
        roundData[_roundData.roundId] = _roundData;
    }

    function updateAnswer(int256 _answer) public {
        latestRoundId++;
        roundData[latestRoundId].roundId = latestRoundId;
        roundData[latestRoundId].answer = _answer;
        roundData[latestRoundId].updatedAt = block.timestamp;
        roundData[latestRoundId].startedAt = block.timestamp;
    }
}
