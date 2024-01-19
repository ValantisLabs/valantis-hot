// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import 'forge-std/Console.sol';

import { SOTBase } from 'test/base/SOTBase.t.sol';
import { SOTOracle } from 'src/SOTOracle.sol';
import { SOTOracleHelper } from 'test/helpers/SOTOracleHelper.sol';

import { AggregatorV3Interface } from 'src/vendor/chainlink/AggregatorV3Interface.sol';
import { MockChainlinkOracle } from 'test/mocks/MockChainlinkOracle.sol';

import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { ERC20 } from 'valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';

contract SOTOracleConcrete is SOTBase {
    SOTOracle public oracle;

    uint256 public MAX_ALLOWED_PRECISION_ERROR = 1; // In base 1e8
    uint256 public PRECISION_BASE = 1e8; // 1% of 1 PIPS

    function setUp() public override {
        super.setUp();

        (feedToken0, feedToken1) = deployChainlinkOracles(8, 8);
        oracle = deploySOTOracleIndependently(feedToken0, feedToken1, 10 minutes);
    }

    function test_constructor() public {
        assertEq(address(oracle.feedToken0()), address(feedToken0));
        assertEq(address(oracle.feedToken1()), address(feedToken1));
        assertEq(oracle.maxOracleUpdateDuration(), 10 minutes);
        assertEq(oracle.feedToken0Base(), 10 ** feedToken0.decimals());
        assertEq(oracle.feedToken1Base(), 10 ** feedToken1.decimals());
        assertEq(oracle.token0Base(), 10 ** ERC20(pool.token0()).decimals());
        assertEq(oracle.token1Base(), 10 ** ERC20(pool.token1()).decimals());
    }

    function test__getOraclePriceUSD() public {
        (feedToken0, feedToken1) = deployChainlinkOracles(18, 6);

        feedToken0.updateAnswer(2000e8);
        feedToken1.updateAnswer(50e8);

        SOTOracleHelper oracleHelper = deploySOTOracleHelper(feedToken0, feedToken1, 10 minutes);

        uint256 price0 = oracleHelper.getOraclePriceUSD(feedToken0);
        uint256 price1 = oracleHelper.getOraclePriceUSD(feedToken1);

        assertEq(price0, 2000e8);
        assertEq(price1, 50e8);
    }

    function test_getSqrtOraclePriceX96_sameTokenDecimals() public {
        // Decimals of token0 = 18
        // Decimals of token1 = 18
        // Decimals of feed0 = 8
        // Decimals of feed1 = 8

        feedToken0.updateAnswer(2000e8); // Assume price of Eth/ USD
        feedToken1.updateAnswer(1e8); // Assume price of USDC/USD

        // Wolfram Alpha Result
        // sqrt( 2000 * 2**192 ) = 3543191142285914205922034323214.52013064235901452874517487228
        // sqrt ( 2000 ) * 2**96 = 3543191142285914205922034323214.52013064235901452874517487228
        uint256 expectedResult = 3543191142285914205922034323214;
        uint256 actualResult = oracle.getSqrtOraclePriceX96();

        assertApproxEqAbs(
            actualResult,
            expectedResult,
            Math.mulDiv(actualResult, MAX_ALLOWED_PRECISION_ERROR, PRECISION_BASE)
        );

        feedToken0.updateAnswer(99999e8);
        feedToken1.updateAnswer(50e8);

        // Wolfram Alpha Result
        // sqrt( 99999 / 50 ) * 2**96 = 3543173426285912665621600323870.79938027911749558699066756057
        expectedResult = 3543173426285912665621600323870;
        actualResult = oracle.getSqrtOraclePriceX96();

        assertApproxEqAbs(
            actualResult,
            expectedResult,
            Math.mulDiv(actualResult, MAX_ALLOWED_PRECISION_ERROR, PRECISION_BASE)
        );

        feedToken0.updateAnswer(99999e8);
        feedToken1.updateAnswer(1);

        // Wolfram Alpha Result
        // sqrt( 99999 * 10**8 ) * 2**96 = 250540195664674272183131378481921689.282610549685547082888064
        expectedResult = 250540195664674272183131378481921689;
        actualResult = oracle.getSqrtOraclePriceX96();

        assertApproxEqAbs(
            actualResult,
            expectedResult,
            Math.mulDiv(actualResult, MAX_ALLOWED_PRECISION_ERROR, PRECISION_BASE)
        );
    }

    function test_getSqrtOraclePriceX96_differentFeedDecimals() public {
        SOTOracleHelper oracleHelper = deploySOTOracleHelper(feedToken0, feedToken1, 10 minutes);

        // Wolfram Alpha Result
        // sqrt ( 5000 ) * 2**96 = 5602277097478613991873193822745.81717623199757051335527508073
        uint256 expectedResult = 5602277097478613991873193822745;
        uint256 actualResult = oracleHelper.calculateSqrtOraclePriceX96(5000e18, 1e6, 1e18, 1e6, 1e18, 1e18);

        assertApproxEqAbs(
            actualResult,
            expectedResult,
            Math.mulDiv(actualResult, MAX_ALLOWED_PRECISION_ERROR, PRECISION_BASE)
        );
    }

    function test_getSqrtOraclePriceX96_differentTokenDecimals() public {
        SOTOracleHelper oracleHelper = deploySOTOracleHelper(feedToken0, feedToken1, 10 minutes);
        // Price: 1 * 1e8   = 5000 * 1e18
        // ==> 1 = 5000 * 1e10
        // Wolfram Alpha Result
        // sqrt ( 5000 * 1e10) * 2**96 = 560227709747861399187319382274581717.623199757051335527508073
        uint256 expectedResult = 560227709747861399187319382274581717;
        uint256 actualResult = oracleHelper.calculateSqrtOraclePriceX96(5000e18, 1e6, 1e18, 1e6, 1e8, 1e18);

        assertApproxEqAbs(
            actualResult,
            expectedResult,
            Math.mulDiv(actualResult, MAX_ALLOWED_PRECISION_ERROR, PRECISION_BASE)
        );
    }

    function test__getOraclePriceUSD_stalePrice() public {
        feedToken0.updateAnswer(99999e8);
        feedToken1.updateAnswer(1);

        vm.warp(block.timestamp + 11 minutes);

        vm.expectRevert(SOTOracle.SOTOracle___getOraclePriceUSD_stalePrice.selector);
        oracle.getSqrtOraclePriceX96();
    }

    function test_getSqrtOraclePriceX96_priceOutOfBounds() public {
        // 1208903099295063476464878.59531099144682633284710852807764469
        feedToken0.updateAnswer(350275971719517849889060729823552339968);
        feedToken1.updateAnswer(1e8);

        vm.expectRevert(SOTOracle.SOTOracle___getSqrtOraclePriceX96_sqrtOraclePriceOutOfBounds.selector);
        oracle.getSqrtOraclePriceX96();
    }
}
