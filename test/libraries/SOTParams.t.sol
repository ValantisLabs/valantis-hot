// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';
import { console } from 'forge-std/console.sol';
import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

import { SOTParams } from 'src/libraries/SOTParams.sol';
import { TightPack } from 'src/libraries/utils/TightPack.sol';
import { SolverOrderType, AMMState } from 'src/structs/SOTStructs.sol';
import { SOTConstants } from 'src/libraries/SOTConstants.sol';

import { SOTBase } from 'test/base/SOTBase.t.sol';

contract SOTParamsHarness {
    using TightPack for AMMState;

    AMMState public ammStateStorage;

    function setState(uint160 a, uint160 b, uint160 c) public {
        ammStateStorage.setState(a, b, c);
    }

    function validateBasicParams(
        SolverOrderType memory sot,
        bool isZeroToOne,
        uint256 amountOut,
        address sender,
        address recipient,
        uint256 amountIn,
        uint256 tokenOutMaxBound,
        uint32 maxDelay,
        uint56 alternatingNonceBitmap
    ) public view {
        SOTParams.validateBasicParams(
            sot,
            isZeroToOne,
            amountOut,
            sender,
            recipient,
            amountIn,
            tokenOutMaxBound,
            maxDelay,
            alternatingNonceBitmap
        );
    }

    function validateFeeParams(
        SolverOrderType memory sot,
        uint16 feeMinBound,
        uint16 feeGrowthMinBound,
        uint16 feeGrowthMaxBound
    ) public pure {
        SOTParams.validateFeeParams(
            sot.feeMinToken0,
            sot.feeMaxToken0,
            sot.feeGrowthE6Token0,
            sot.feeMinToken1,
            sot.feeMaxToken1,
            sot.feeGrowthE6Token1,
            feeMinBound,
            feeGrowthMinBound,
            feeGrowthMaxBound
        );
    }

    function validatePriceConsistency(
        uint160 sqrtSolverPriceX96,
        uint160 sqrtSpotPriceNewX96,
        uint160 sqrtOraclePriceX96,
        uint256 maxOracleDeviationBipsLower,
        uint256 maxOracleDeviationBipsUpper,
        uint256 solverMaxDiscountBips
    ) public view {
        SOTParams.validatePriceConsistency(
            ammStateStorage,
            sqrtSolverPriceX96,
            sqrtSpotPriceNewX96,
            sqrtOraclePriceX96,
            maxOracleDeviationBipsLower,
            maxOracleDeviationBipsUpper,
            solverMaxDiscountBips
        );
    }

    function validatePriceBounds(
        uint160 sqrtSpotPriceX96,
        uint160 sqrtPriceLowX96,
        uint160 sqrtPriceHighX96
    ) public pure {
        SOTParams.validatePriceBounds(sqrtSpotPriceX96, sqrtPriceLowX96, sqrtPriceHighX96);
    }

    function hashParams(SolverOrderType memory sotParams) public pure returns (bytes32) {
        return SOTParams.hashParams(sotParams);
    }

    function checkPriceDeviation(
        uint256 sqrtPriceAX96,
        uint256 sqrtPriceBX96,
        uint256 maxDeviationInBipsLower,
        uint256 maxDeviationInBipsUpper
    ) public pure returns (bool) {
        return
            SOTParams.checkPriceDeviation(
                sqrtPriceAX96,
                sqrtPriceBX96,
                maxDeviationInBipsLower,
                maxDeviationInBipsUpper
            );
    }
}

contract TestSOTParams is SOTBase {
    using SafeCast for uint256;

    SOTParamsHarness harness;

    // Default Contract Storage
    uint256 public tokenOutMaxBound = 1000e18;
    uint32 public maxDelay = 36; // 3 Blocks
    uint56 public alternatingNonceBitmap = 2; // 0b10

    function setUp() public override {
        super.setUp();
        vm.warp(1e6);
        harness = new SOTParamsHarness();
    }

    function test_validateBasicParams() public {
        SolverOrderType memory sotParams = _getSensibleSOTParams();

        sotParams.expectedFlag = 1;
        // Correct Case
        harness.validateBasicParams({
            sot: sotParams,
            isZeroToOne: true,
            amountOut: 500e18,
            sender: address(this),
            recipient: makeAddr('RECIPIENT'),
            amountIn: 100e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });
    }

    function test_validateBasicParams_expiredQuote() public {
        SolverOrderType memory sotParams = _getSensibleSOTParams();
        sotParams.signatureTimestamp = (block.timestamp - 25).toUint32();
        vm.expectRevert(SOTParams.SOTParams__validateBasicParams_quoteExpired.selector);
        harness.validateBasicParams({
            sot: sotParams,
            isZeroToOne: true,
            amountOut: 500e18,
            sender: address(this),
            recipient: makeAddr('RECIPIENT'),
            amountIn: 100e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });
    }

    function test_validateBasicParams_excessiveExpiry() public {
        SolverOrderType memory sotParams = _getSensibleSOTParams();
        sotParams.expiry = 37;

        vm.expectRevert(SOTParams.SOTParams__validateBasicParams_excessiveExpiryTime.selector);
        harness.validateBasicParams({
            sot: sotParams,
            isZeroToOne: true,
            amountOut: 500e18,
            sender: address(this),
            recipient: makeAddr('RECIPIENT'),
            amountIn: 100e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });
    }

    function test_validateBasicParams_incorrectSenderRecipient() public {
        SolverOrderType memory sotParams = _getSensibleSOTParams();

        // Incorrect Recipient
        vm.expectRevert(SOTParams.SOTParams__validateBasicParams_unauthorizedRecipient.selector);
        harness.validateBasicParams({
            sot: sotParams,
            isZeroToOne: true,
            amountOut: 500e18,
            sender: address(this),
            recipient: makeAddr('WRONG_RECIPIENT'),
            amountIn: 100e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });

        // Incorrect Sender
        vm.expectRevert(SOTParams.SOTParams__validateBasicParams_unauthorizedSender.selector);
        harness.validateBasicParams({
            sot: sotParams,
            isZeroToOne: true,
            amountOut: 500e18,
            sender: makeAddr('WRONG_SENDER'),
            recipient: makeAddr('RECIPIENT'),
            amountIn: 100e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });
    }

    function test_validateBasicParams_excessiveTokenAmounts() public {
        SolverOrderType memory sotParams = _getSensibleSOTParams();

        vm.expectRevert(SOTParams.SOTParams__validateBasicParams_excessiveTokenInAmount.selector);
        harness.validateBasicParams({
            sot: sotParams,
            isZeroToOne: true,
            amountOut: 500e18,
            sender: address(this),
            recipient: makeAddr('RECIPIENT'),
            amountIn: 101e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });

        vm.expectRevert(SOTParams.SOTParams__validateBasicParams_excessiveTokenOutAmountRequested.selector);
        harness.validateBasicParams({
            sot: sotParams,
            isZeroToOne: true,
            amountOut: 1000e18 + 1,
            sender: address(this),
            recipient: makeAddr('RECIPIENT'),
            amountIn: 100e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });
    }

    function test_validateBasicParams_replayedQuote() public {
        SolverOrderType memory sotParams = _getSensibleSOTParams();

        sotParams.expectedFlag = 0;
        vm.expectRevert(SOTParams.SOTParams__validateBasicParams_replayedQuote.selector);
        harness.validateBasicParams({
            sot: sotParams,
            isZeroToOne: true,
            amountOut: 500e18,
            sender: address(this),
            recipient: makeAddr('RECIPIENT'),
            amountIn: 100e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });
    }

    function test_validateFeeParams() public {
        SolverOrderType memory sotParams = _getSensibleSOTParams();

        // Correct Case
        harness.validateFeeParams(sotParams, 1, 100, 1000);

        // // Incorrect Cases
        // 1. Fee Growth out of min & max bounds
        vm.expectRevert(SOTParams.SOTParams__validateFeeParams_invalidfeeGrowthE6.selector);
        harness.validateFeeParams(sotParams, 1, 600, 1000);

        vm.expectRevert(SOTParams.SOTParams__validateFeeParams_invalidfeeGrowthE6.selector);
        harness.validateFeeParams(sotParams, 1, 100, 400);

        // 2. Insufficient Fee Min
        vm.expectRevert(SOTParams.SOTParams__validateFeeParams_insufficientFee.selector);
        harness.validateFeeParams(sotParams, 11, 100, 1000);

        // 3. Invalid Fee Max
        sotParams.feeMaxToken0 = 1e4;
        vm.expectRevert(SOTParams.SOTParams__validateFeeParams_invalidFeeMax.selector);
        harness.validateFeeParams(sotParams, 1, 100, 1000);

        // 4. Invalid Fee Min
        sotParams.feeMaxToken0 = 1e2;
        sotParams.feeMinToken0 = 1e2 + 1;

        vm.expectRevert(SOTParams.SOTParams__validateFeeParams_invalidFeeMin.selector);
        harness.validateFeeParams(sotParams, 1, 100, 1000);
    }

    function test_validatePriceConsistency() public {
        harness.setState(100, 1, 1000);

        // more than 20%
        uint160 sqrtSolverPrice = 111; // Price = 12100
        uint160 sqrtNewPrice = 100; // Price = 10000

        (uint256 maxOracleDeviationBipsLower, uint256 maxOracleDeviationBipsUpper) = getSqrtDeviationValues(2000);

        // Bound Lower = 2000 ( 20% of 10000)
        vm.expectRevert(SOTParams.SOTParams__validatePriceConsistency_solverAndSpotPriceNewExcessiveDeviation.selector);
        harness.validatePriceConsistency(
            sqrtSolverPrice,
            sqrtNewPrice,
            100,
            maxOracleDeviationBipsLower,
            maxOracleDeviationBipsUpper,
            2000
        );

        sqrtNewPrice = 101;
        uint160 sqrtOraclePrice = 126;
        vm.expectRevert(SOTParams.SOTParams__validatePriceConsistency_spotAndOraclePricesExcessiveDeviation.selector);
        harness.validatePriceConsistency(
            sqrtSolverPrice,
            sqrtNewPrice,
            sqrtOraclePrice,
            maxOracleDeviationBipsLower,
            maxOracleDeviationBipsUpper,
            2000
        );

        sqrtOraclePrice = 110;
        sqrtNewPrice = 95;
        vm.expectRevert(
            SOTParams.SOTParams__validatePriceConsistency_newSpotAndOraclePricesExcessiveDeviation.selector
        );
        harness.validatePriceConsistency(
            sqrtSolverPrice,
            sqrtNewPrice,
            sqrtOraclePrice,
            maxOracleDeviationBipsLower,
            maxOracleDeviationBipsUpper,
            2000
        );

        harness.setState(
            SOTConstants.MIN_SQRT_PRICE + 100,
            SOTConstants.MIN_SQRT_PRICE + 1,
            SOTConstants.MIN_SQRT_PRICE + 1000
        );

        sqrtSolverPrice = SOTConstants.MIN_SQRT_PRICE + 101;
        sqrtOraclePrice = SOTConstants.MIN_SQRT_PRICE + 120;
        sqrtNewPrice = SOTConstants.MIN_SQRT_PRICE + 100;

        harness.validatePriceConsistency(
            sqrtSolverPrice,
            sqrtNewPrice,
            sqrtOraclePrice,
            maxOracleDeviationBipsLower,
            maxOracleDeviationBipsUpper,
            2000
        );
    }

    function test_validatePriceBounds() public {
        uint160 priceLow = SOTConstants.MIN_SQRT_PRICE + 10;
        uint160 priceHigh = SOTConstants.MIN_SQRT_PRICE + 1000;

        uint160 price = SOTConstants.MIN_SQRT_PRICE + 5;
        vm.expectRevert(SOTParams.SOTParams__validatePriceBounds_newSpotPriceOutOfBounds.selector);
        harness.validatePriceBounds(price, priceLow, priceHigh);

        price = SOTConstants.MIN_SQRT_PRICE + 2000;
        vm.expectRevert(SOTParams.SOTParams__validatePriceBounds_newSpotPriceOutOfBounds.selector);
        harness.validatePriceBounds(price, priceLow, priceHigh);

        price = SOTConstants.MIN_SQRT_PRICE;
        vm.expectRevert(SOTParams.SOTParams__validatePriceBounds_newSpotPriceOutOfBounds.selector);
        harness.validatePriceBounds(price, priceLow, priceHigh);

        price = SOTConstants.MAX_SQRT_PRICE;
        vm.expectRevert(SOTParams.SOTParams__validatePriceBounds_newSpotPriceOutOfBounds.selector);
        harness.validatePriceBounds(price, priceLow, priceHigh);

        price = SOTConstants.MIN_SQRT_PRICE + 11;
        harness.validatePriceBounds(price, priceLow, priceHigh);
    }

    function test_hashParams() public {
        SolverOrderType memory sotParams;

        bytes32 expectedHash = keccak256(abi.encode(SOTConstants.SOT_TYPEHASH, sotParams));

        assertEq(expectedHash, harness.hashParams(sotParams));
    }

    function test_checkPriceDeviation() public {
        uint256 sqrtPriceA = 110; // True price = 12100
        uint256 sqrtPriceB = 100; // True price = 10000

        uint256 truePriceAllowedDeviation = 2000; // 20%
        // Spot Price Lower Allowed = 8000
        // Spot Price Upper Allowed = 12000
        // Sqrt Price Lower Allowed = 89.44
        // Sqrt Price Upper Allowed = 109.54
        // Sqrt Lower Deviation = 1056
        // Sqrt Upper Deviation = 954

        uint256 maxDeviationInBipsLower = 1056;
        uint256 maxDeviationInBipsUpper = 954;

        (uint256 calculatedDeviationLower, uint256 calculatedDeviationUpper) = getSqrtDeviationValues(
            truePriceAllowedDeviation
        );

        assertEq(calculatedDeviationLower, maxDeviationInBipsLower, 'Lower Deviation Mismatch');
        assertEq(calculatedDeviationUpper, maxDeviationInBipsUpper, 'Upper Deviation Mismatch');

        // harness.checkPriceDeviation(sqrtPriceA, sqrtPriceB, maxDeviationInBipsLower, maxDeviationInBipsUpper);

        assertFalse(
            harness.checkPriceDeviation(sqrtPriceA, sqrtPriceB, maxDeviationInBipsLower, maxDeviationInBipsUpper)
        );

        console.log(sqrtPriceB * maxDeviationInBipsUpper);
    }
}
