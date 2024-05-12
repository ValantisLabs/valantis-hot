// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';
import { console } from 'forge-std/console.sol';
import { SafeCast } from '../../lib/valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import { ALMLiquidityQuoteInput } from '../../lib/valantis-core/src/alm/interfaces/ISovereignALM.sol';

import { HOTParams } from '../../src/libraries/HOTParams.sol';
import { TightPack } from '../../src/libraries/utils/TightPack.sol';
import { HybridOrderType, AMMState } from '../../src/structs/HOTStructs.sol';
import { HOTConstants } from '../../src/libraries/HOTConstants.sol';

import { HOTBase } from '../base/HOTBase.t.sol';

contract HOTParamsHarness {
    using TightPack for AMMState;

    AMMState public ammStateStorage;

    function setState(uint160 a, uint160 b, uint160 c) public {
        ammStateStorage.setState(a, b, c);
    }

    function validateBasicParams(
        HybridOrderType memory hot,
        ALMLiquidityQuoteInput memory almLiquidityQuoteInput,
        uint256 amountOut,
        uint256 tokenOutMaxBound,
        uint32 maxDelay,
        uint56 alternatingNonceBitmap
    ) public view {
        HOTParams.validateBasicParams(
            hot,
            almLiquidityQuoteInput,
            amountOut,
            tokenOutMaxBound,
            maxDelay,
            alternatingNonceBitmap
        );
    }

    function validateFeeParams(
        HybridOrderType memory hot,
        uint16 feeMinBound,
        uint16 feeGrowthMinBound,
        uint16 feeGrowthMaxBound
    ) public pure {
        HOTParams.validateFeeParams(
            hot.feeMinToken0,
            hot.feeMaxToken0,
            hot.feeGrowthE6Token0,
            hot.feeMinToken1,
            hot.feeMaxToken1,
            hot.feeGrowthE6Token1,
            feeMinBound,
            feeGrowthMinBound,
            feeGrowthMaxBound
        );
    }

    function validatePriceConsistency(
        uint160 sqrtHotPriceX96,
        uint160 sqrtSpotPriceNewX96,
        uint160 sqrtOraclePriceX96,
        uint256 maxOracleDeviationBipsLower,
        uint256 maxOracleDeviationBipsUpper,
        uint256 hotMaxDiscountBipsLower,
        uint256 hotMaxDiscountBipsUpper
    ) public view {
        HOTParams.validatePriceConsistency(
            ammStateStorage,
            sqrtHotPriceX96,
            sqrtSpotPriceNewX96,
            sqrtOraclePriceX96,
            maxOracleDeviationBipsLower,
            maxOracleDeviationBipsUpper,
            hotMaxDiscountBipsLower,
            hotMaxDiscountBipsUpper
        );
    }

    function validatePriceBounds(
        uint160 sqrtSpotPriceX96,
        uint160 sqrtPriceLowX96,
        uint160 sqrtPriceHighX96
    ) public pure {
        HOTParams.validatePriceBounds(sqrtSpotPriceX96, sqrtPriceLowX96, sqrtPriceHighX96);
    }

    function hashParams(HybridOrderType memory hotParams) public pure returns (bytes32) {
        return HOTParams.hashParams(hotParams);
    }

    function checkPriceDeviation(
        uint256 sqrtPriceAX96,
        uint256 sqrtPriceBX96,
        uint256 maxDeviationInBipsLower,
        uint256 maxDeviationInBipsUpper
    ) public pure returns (bool) {
        return
            HOTParams.checkPriceDeviation(
                sqrtPriceAX96,
                sqrtPriceBX96,
                maxDeviationInBipsLower,
                maxDeviationInBipsUpper
            );
    }
}

contract TestHOTParams is HOTBase {
    using SafeCast for uint256;

    HOTParamsHarness harness;

    // Default Contract Storage
    uint256 public tokenOutMaxBound = 1000e18;
    uint32 public maxDelay = 36; // 3 Blocks
    uint56 public alternatingNonceBitmap = 2; // 0b10

    function setUp() public override {
        super.setUp();
        vm.warp(1e6);
        harness = new HOTParamsHarness();
    }

    function test_validateBasicParams() public {
        HybridOrderType memory hotParams = _getSensibleHOTParams();

        hotParams.expectedFlag = 1;
        // Correct Case

        ALMLiquidityQuoteInput memory almLiquidityQuoteInput;
        almLiquidityQuoteInput.isZeroToOne = true;
        almLiquidityQuoteInput.amountInMinusFee = 100e18;
        almLiquidityQuoteInput.sender = address(this);
        almLiquidityQuoteInput.recipient = makeAddr('RECIPIENT');

        harness.validateBasicParams({
            hot: hotParams,
            almLiquidityQuoteInput: almLiquidityQuoteInput,
            amountOut: 500e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });
    }

    function test_validateBasicParams_expiredQuote() public {
        HybridOrderType memory hotParams = _getSensibleHOTParams();
        hotParams.signatureTimestamp = (block.timestamp - 25).toUint32();

        ALMLiquidityQuoteInput memory almLiquidityQuoteInput;
        almLiquidityQuoteInput.isZeroToOne = true;
        almLiquidityQuoteInput.amountInMinusFee = 100e18;
        almLiquidityQuoteInput.sender = address(this);
        almLiquidityQuoteInput.recipient = makeAddr('RECIPIENT');

        vm.expectRevert(HOTParams.HOTParams__validateBasicParams_quoteExpired.selector);
        harness.validateBasicParams({
            hot: hotParams,
            almLiquidityQuoteInput: almLiquidityQuoteInput,
            amountOut: 500e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });
    }

    function test_validateBasicParams_excessiveExpiry() public {
        HybridOrderType memory hotParams = _getSensibleHOTParams();
        hotParams.expiry = 37;

        ALMLiquidityQuoteInput memory almLiquidityQuoteInput;
        almLiquidityQuoteInput.isZeroToOne = true;
        almLiquidityQuoteInput.amountInMinusFee = 100e18;
        almLiquidityQuoteInput.sender = address(this);
        almLiquidityQuoteInput.recipient = makeAddr('RECIPIENT');

        vm.expectRevert(HOTParams.HOTParams__validateBasicParams_excessiveExpiryTime.selector);
        harness.validateBasicParams({
            hot: hotParams,
            almLiquidityQuoteInput: almLiquidityQuoteInput,
            amountOut: 500e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });
    }

    function test_validateBasicParams_incorrectSenderRecipient() public {
        HybridOrderType memory hotParams = _getSensibleHOTParams();

        ALMLiquidityQuoteInput memory almLiquidityQuoteInput;
        almLiquidityQuoteInput.isZeroToOne = true;
        almLiquidityQuoteInput.amountInMinusFee = 100e18;
        almLiquidityQuoteInput.sender = address(this);
        almLiquidityQuoteInput.recipient = makeAddr('WRONG_RECIPIENT');

        // Incorrect Recipient
        vm.expectRevert(HOTParams.HOTParams__validateBasicParams_unauthorizedRecipient.selector);
        harness.validateBasicParams({
            hot: hotParams,
            almLiquidityQuoteInput: almLiquidityQuoteInput,
            amountOut: 500e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });

        almLiquidityQuoteInput.sender = makeAddr('WRONG_SENDER');
        almLiquidityQuoteInput.recipient = makeAddr('RECIPIENT');

        // Incorrect Sender
        vm.expectRevert(HOTParams.HOTParams__validateBasicParams_unauthorizedSender.selector);
        harness.validateBasicParams({
            hot: hotParams,
            almLiquidityQuoteInput: almLiquidityQuoteInput,
            amountOut: 500e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });
    }

    function test_validateBasicParams_excessiveTokenAmounts() public {
        HybridOrderType memory hotParams = _getSensibleHOTParams();

        ALMLiquidityQuoteInput memory almLiquidityQuoteInput;
        almLiquidityQuoteInput.isZeroToOne = true;
        almLiquidityQuoteInput.amountInMinusFee = 101e18;
        almLiquidityQuoteInput.sender = address(this);
        almLiquidityQuoteInput.recipient = makeAddr('RECIPIENT');

        vm.expectRevert(HOTParams.HOTParams__validateBasicParams_excessiveTokenInAmount.selector);
        harness.validateBasicParams({
            hot: hotParams,
            almLiquidityQuoteInput: almLiquidityQuoteInput,
            amountOut: 500e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });

        almLiquidityQuoteInput.amountInMinusFee = 100e18;

        vm.expectRevert(HOTParams.HOTParams__validateBasicParams_excessiveTokenOutAmountRequested.selector);
        harness.validateBasicParams({
            hot: hotParams,
            almLiquidityQuoteInput: almLiquidityQuoteInput,
            amountOut: 1000e18 + 1,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });
    }

    function test_validateBasicParams_replayedQuote() public {
        HybridOrderType memory hotParams = _getSensibleHOTParams();

        hotParams.expectedFlag = 0;

        ALMLiquidityQuoteInput memory almLiquidityQuoteInput;
        almLiquidityQuoteInput.isZeroToOne = true;
        almLiquidityQuoteInput.amountInMinusFee = 100e18;
        almLiquidityQuoteInput.sender = address(this);
        almLiquidityQuoteInput.recipient = makeAddr('RECIPIENT');

        vm.expectRevert(HOTParams.HOTParams__validateBasicParams_replayedQuote.selector);
        harness.validateBasicParams({
            hot: hotParams,
            almLiquidityQuoteInput: almLiquidityQuoteInput,
            amountOut: 500e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });
    }

    function test_validateFeeParams() public {
        HybridOrderType memory hotParams = _getSensibleHOTParams();

        // Correct Case
        harness.validateFeeParams(hotParams, 1, 100, 1000);

        // // Incorrect Cases
        // 1. Fee Growth out of min & max bounds
        vm.expectRevert(HOTParams.HOTParams__validateFeeParams_invalidfeeGrowthE6.selector);
        harness.validateFeeParams(hotParams, 1, 600, 1000);

        vm.expectRevert(HOTParams.HOTParams__validateFeeParams_invalidfeeGrowthE6.selector);
        harness.validateFeeParams(hotParams, 1, 100, 400);

        // 2. Insufficient Fee Min
        vm.expectRevert(HOTParams.HOTParams__validateFeeParams_insufficientFee.selector);
        harness.validateFeeParams(hotParams, 11, 100, 1000);

        // 3. Invalid Fee Max
        hotParams.feeMaxToken0 = 1e4;
        vm.expectRevert(HOTParams.HOTParams__validateFeeParams_invalidFeeMax.selector);
        harness.validateFeeParams(hotParams, 1, 100, 1000);

        // 4. Invalid Fee Min
        hotParams.feeMaxToken0 = 1e2;
        hotParams.feeMinToken0 = 1e2 + 1;

        vm.expectRevert(HOTParams.HOTParams__validateFeeParams_invalidFeeMin.selector);
        harness.validateFeeParams(hotParams, 1, 100, 1000);
    }

    function test_validatePriceConsistency() public {
        harness.setState(100, 1, 1000);

        // more than 20%
        uint160 sqrtHotPrice = 110; // Price = 12100
        uint160 sqrtNewPrice = 100; // Price = 10000

        (uint256 maxDeviationBipsLower, uint256 maxDeviationBipsUpper) = getSqrtDeviationValues(2000);

        // Bound Lower = 2000 ( 20% of 10000)
        vm.expectRevert(HOTParams.HOTParams__validatePriceConsistency_hotAndSpotPriceNewExcessiveDeviation.selector);
        harness.validatePriceConsistency(
            sqrtHotPrice,
            sqrtNewPrice,
            100,
            maxDeviationBipsLower,
            maxDeviationBipsUpper,
            maxDeviationBipsLower,
            maxDeviationBipsUpper
        );

        sqrtNewPrice = 101;
        uint160 sqrtOraclePrice = 126;
        sqrtHotPrice = 109;
        vm.expectRevert(HOTParams.HOTParams__validatePriceConsistency_spotAndOraclePricesExcessiveDeviation.selector);
        harness.validatePriceConsistency(
            sqrtHotPrice,
            sqrtNewPrice,
            sqrtOraclePrice,
            maxDeviationBipsLower,
            maxDeviationBipsUpper,
            maxDeviationBipsLower,
            maxDeviationBipsUpper
        );

        sqrtOraclePrice = 110;
        sqrtNewPrice = 95;
        sqrtHotPrice = 100;
        vm.expectRevert(
            HOTParams.HOTParams__validatePriceConsistency_newSpotAndOraclePricesExcessiveDeviation.selector
        );
        harness.validatePriceConsistency(
            sqrtHotPrice,
            sqrtNewPrice,
            sqrtOraclePrice,
            maxDeviationBipsLower,
            maxDeviationBipsUpper,
            maxDeviationBipsLower,
            maxDeviationBipsUpper
        );

        harness.setState(
            HOTConstants.MIN_SQRT_PRICE + 100,
            HOTConstants.MIN_SQRT_PRICE + 1,
            HOTConstants.MIN_SQRT_PRICE + 1000
        );

        sqrtHotPrice = HOTConstants.MIN_SQRT_PRICE + 101;
        sqrtOraclePrice = HOTConstants.MIN_SQRT_PRICE + 120;
        sqrtNewPrice = HOTConstants.MIN_SQRT_PRICE + 100;

        harness.validatePriceConsistency(
            sqrtHotPrice,
            sqrtNewPrice,
            sqrtOraclePrice,
            maxDeviationBipsLower,
            maxDeviationBipsUpper,
            maxDeviationBipsLower,
            maxDeviationBipsUpper
        );
    }

    function test_validatePriceBounds() public {
        uint160 priceLow = HOTConstants.MIN_SQRT_PRICE + 10;
        uint160 priceHigh = HOTConstants.MIN_SQRT_PRICE + 1000;

        uint160 price = HOTConstants.MIN_SQRT_PRICE + 5;
        vm.expectRevert(HOTParams.HOTParams__validatePriceBounds_newSpotPriceOutOfBounds.selector);
        harness.validatePriceBounds(price, priceLow, priceHigh);

        price = HOTConstants.MIN_SQRT_PRICE + 2000;
        vm.expectRevert(HOTParams.HOTParams__validatePriceBounds_newSpotPriceOutOfBounds.selector);
        harness.validatePriceBounds(price, priceLow, priceHigh);

        price = HOTConstants.MIN_SQRT_PRICE;
        vm.expectRevert(HOTParams.HOTParams__validatePriceBounds_newSpotPriceOutOfBounds.selector);
        harness.validatePriceBounds(price, priceLow, priceHigh);

        price = HOTConstants.MAX_SQRT_PRICE;
        vm.expectRevert(HOTParams.HOTParams__validatePriceBounds_newSpotPriceOutOfBounds.selector);
        harness.validatePriceBounds(price, priceLow, priceHigh);

        price = HOTConstants.MIN_SQRT_PRICE + 11;
        harness.validatePriceBounds(price, priceLow, priceHigh);
    }

    function test_hashParams() public {
        HybridOrderType memory hotParams;

        bytes32 expectedHash = keccak256(abi.encode(HOTConstants.HOT_TYPEHASH, hotParams));

        assertEq(expectedHash, harness.hashParams(hotParams));
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
