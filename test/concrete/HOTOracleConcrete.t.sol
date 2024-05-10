// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Math } from '../../lib/valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { ERC20 } from '../../lib/valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';

import { HOTOracle } from '../../src/HOTOracle.sol';
import { AggregatorV3Interface } from '../../src/vendor/chainlink/AggregatorV3Interface.sol';

import { MockChainlinkOracle } from '../mocks/MockChainlinkOracle.sol';
import { MockToken } from '../mocks/MockToken.sol';
import { HOTBase } from '../base/HOTBase.t.sol';
import { HOTOracleHelper } from '../helpers/HOTOracleHelper.sol';

contract HOTOracleConcrete is HOTBase {
    HOTOracle public oracle;

    uint32 ORACLE_FEED_UPDATE_PERIOD = 10 minutes;

    function setUp() public override {
        super.setUp();

        (feedToken0, feedToken1) = deployChainlinkOracles(8, 8);
        oracle = deployHOTOracleIndependently(
            feedToken0,
            feedToken1,
            ORACLE_FEED_UPDATE_PERIOD,
            ORACLE_FEED_UPDATE_PERIOD
        );
    }

    function test_constructor() public {
        // Check correct initialization
        assertEq(address(oracle.feedToken0()), address(feedToken0));
        assertEq(address(oracle.feedToken1()), address(feedToken1));
        assertEq(oracle.maxOracleUpdateDurationFeed0(), 10 minutes);
        assertEq(oracle.maxOracleUpdateDurationFeed1(), 10 minutes);
    }

    function test_setFeeds() public {
        (feedToken0, feedToken1) = deployChainlinkOracles(18, 6);

        HOTOracleHelper oracleHelper = deployHOTOracleHelper(
            address(token0),
            address(token1),
            MockChainlinkOracle(address(0)),
            MockChainlinkOracle(address(0)),
            ORACLE_FEED_UPDATE_PERIOD,
            ORACLE_FEED_UPDATE_PERIOD
        );

        vm.expectRevert(HOTOracle.HOTOracle___setFeeds_newFeedsCannotBeZero.selector);
        oracleHelper.setFeeds(address(0), address(1));

        vm.expectRevert(HOTOracle.HOTOracle___setFeeds_newFeedsCannotBeZero.selector);
        oracleHelper.setFeeds(address(1), address(0));

        oracleHelper.setFeeds(address(feedToken0), address(feedToken1));

        assertEq(address(oracleHelper.feedToken0()), address(feedToken0));
        assertEq(address(oracleHelper.feedToken1()), address(feedToken1));

        vm.expectRevert(HOTOracle.HOTOracle___setFeeds_feedsAlreadySet.selector);
        oracleHelper.setFeeds(address(1), address(1));
    }

    function test__getOraclePriceUSD() public {
        (feedToken0, feedToken1) = deployChainlinkOracles(18, 6);

        feedToken0.updateAnswer(2000e8);
        feedToken1.updateAnswer(50e8);

        HOTOracleHelper oracleHelper = deployHOTOracleHelper(
            address(token0),
            address(token1),
            feedToken0,
            feedToken1,
            ORACLE_FEED_UPDATE_PERIOD,
            ORACLE_FEED_UPDATE_PERIOD
        );

        uint256 price0 = oracleHelper.getOraclePriceUSD(feedToken0, ORACLE_FEED_UPDATE_PERIOD);
        uint256 price1 = oracleHelper.getOraclePriceUSD(feedToken1, ORACLE_FEED_UPDATE_PERIOD);

        assertEq(price0, 2000e8);
        assertEq(price1, 50e8);
    }

    function test_getSqrtOraclePriceX96_sameTokenAndFeedDecimals() public {
        // Decimals of token0 = 18
        // Decimals of token1 = 18
        // Decimals of feed0 = 8
        // Decimals of feed1 = 8

        feedToken0.updateAnswer(2000e8); // Assume price of Eth/ USD
        feedToken1.updateAnswer(1e8); // Assume price of USDC/USD

        // Wolfram Alpha Result:
        // floor(sqrt( 2000 * 2 ** 96)) * 2**48
        uint256 expectedResult = 3543191142285914096597660073984;
        uint256 actualResult = oracle.getSqrtOraclePriceX96();
        assertEq(actualResult, expectedResult);

        feedToken0.updateAnswer(99999e8);
        feedToken1.updateAnswer(50e8);

        // Wolfram Alpha Result:
        // floor(sqrt( 99999 * 2 ** 96 / 50 )) * 2**48
        expectedResult = 3543173426285912584985405030400;
        actualResult = oracle.getSqrtOraclePriceX96();
        assertEq(actualResult, expectedResult);

        feedToken0.updateAnswer(99999e8);
        feedToken1.updateAnswer(1);

        // Wolfram Alpha Result
        // floor(sqrt( 99999 * 10**8 * 2 ** 96 )) * 2**48
        expectedResult = 250540195664674272183070372680171520;
        actualResult = oracle.getSqrtOraclePriceX96();
        assertEq(actualResult, expectedResult);
    }

    function test_getSqrtOraclePriceX96_differentFeedDecimals() public {
        // Decimals of token0 = 18
        // Decimals of token1 = 18
        // Decimals of feed0 = 18
        // Decimals of feed1 = 6

        HOTOracleHelper oracleHelper = deployHOTOracleHelper(
            address(token0),
            address(token1),
            feedToken0,
            feedToken1,
            ORACLE_FEED_UPDATE_PERIOD,
            ORACLE_FEED_UPDATE_PERIOD
        );

        // Wolfram Alpha Result
        // floor(sqrt( 5000 * 2 ** 96 )) * 2**48
        uint256 expectedResult = 5602277097478613917437299523584;
        uint256 actualResult = oracleHelper.calculateSqrtOraclePriceX96(5000e18, 1e6, 1e18, 1e6);
        assertEq(actualResult, expectedResult);
    }

    function test_getSqrtOraclePriceX96_differentTokenDecimals() public {
        // Decimals of token0 = 8
        // Decimals of token1 = 18
        // Decimals of feed0 = 18
        // Decimals of feed1 = 18

        MockToken _token0 = new MockToken('Token0', '', 8);
        MockToken _token1 = new MockToken('Token1', '', 18);

        HOTOracleHelper oracleHelper = deployHOTOracleHelper(
            address(_token0),
            address(_token1),
            feedToken0,
            feedToken1,
            ORACLE_FEED_UPDATE_PERIOD,
            ORACLE_FEED_UPDATE_PERIOD
        );
        // Wolfram Alpha Result
        // floor(sqrt( 5000 * 1e10 * 2 ** 96)) * 2**48
        uint256 expectedResult = 560227709747861399187054236494987264;
        uint256 actualResult = oracleHelper.calculateSqrtOraclePriceX96(5000e18, 1e18, 1e18, 1e18);
        assertEq(actualResult, expectedResult);
    }

    function test__getOraclePriceUSD_stalePrice() public {
        feedToken0.updateAnswer(99999e8);
        feedToken1.updateAnswer(1);

        vm.warp(block.timestamp + 11 minutes);

        // Check error on stale oracle price update (older than 10 minutes)
        vm.expectRevert(HOTOracle.HOTOracle___getOraclePriceUSD_stalePrice.selector);
        oracle.getSqrtOraclePriceX96();
    }

    function test_getSqrtOraclePriceX96_priceOutOfBounds() public {
        feedToken0.updateAnswer(1);
        feedToken1.updateAnswer(1e38);

        // Check error if price is below minimum bound
        vm.expectRevert(HOTOracle.HOTOracle___getSqrtOraclePriceX96_sqrtOraclePriceOutOfBounds.selector);
        oracle.getSqrtOraclePriceX96();

        // sqrt(MAX_SQRT_PRICE) = 1208903099295063476464878.59531099144682633284710852807764469
        // floor(sqrt(MAX_SQRT_PRICE) = 1208903099295063476464878
        // floor(sqrt(MAX_SQRT_PRICE)) * 2**48 = 340275971719517849889060729823552339968
        feedToken0.updateAnswer(340275971719517849889060729823552339968e8);
        feedToken1.updateAnswer(1e8);

        // Check error if price is above minimum bound
        vm.expectRevert(HOTOracle.HOTOracle___getSqrtOraclePriceX96_sqrtOraclePriceOutOfBounds.selector);
        oracle.getSqrtOraclePriceX96();
    }
}
