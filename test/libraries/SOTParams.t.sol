// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';
import { console } from 'forge-std/console.sol';
import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

import { SOTParams } from 'src/libraries/SOTParams.sol';
import { SOTParamsHelper } from 'test/helpers/SOTParamsHelper.sol';
import { SolverOrderType } from 'src/structs/SOTStructs.sol';
import { SOTConstants } from 'src/libraries/SOTConstants.sol';

import { SOTBase } from 'test/base/SOTBase.t.sol';


contract TestSOTParams is SOTBase {
    using SafeCast for uint256;

    SOTParamsHelper sotParamsHelper;

    // Default Contract Storage
    uint256 public tokenOutMaxBound = 1000e18;
    uint32 public maxDelay = 36; // 3 Blocks
    uint56 public alternatingNonceBitmap = 2; // 0b10

    function setUp() public override {
        super.setUp();

        vm.warp(1e6);
        sotParamsHelper = new SOTParamsHelper();
    }

    function test_validateBasicParams() public {
        SolverOrderType memory sotParams = _getSensibleSOTParams();

        sotParams.expectedFlag = 1;
        // Correct Case
        sotParamsHelper.validateBasicParams({
            sot: sotParams,
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
        sotParamsHelper.validateBasicParams({
            sot: sotParams,
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
        sotParamsHelper.validateBasicParams({
            sot: sotParams,
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
        sotParamsHelper.validateBasicParams({
            sot: sotParams,
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
        sotParamsHelper.validateBasicParams({
            sot: sotParams,
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
        sotParamsHelper.validateBasicParams({
            sot: sotParams,
            amountOut: 500e18,
            sender: address(this),
            recipient: makeAddr('RECIPIENT'),
            amountIn: 101e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });

        vm.expectRevert(SOTParams.SOTParams__validateBasicParams_excessiveTokenOutAmountRequested.selector);
        sotParamsHelper.validateBasicParams({
            sot: sotParams,
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
        sotParamsHelper.validateBasicParams({
            sot: sotParams,
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
        sotParamsHelper.validateFeeParams(sotParams, 1, 100, 1000);

        // // Incorrect Cases
        // 1. Fee Growth out of min & max bounds
        vm.expectRevert(SOTParams.SOTParams__validateFeeParams_invalidfeeGrowthInPips.selector);
        sotParamsHelper.validateFeeParams(sotParams, 1, 600, 1000);

        vm.expectRevert(SOTParams.SOTParams__validateFeeParams_invalidfeeGrowthInPips.selector);
        sotParamsHelper.validateFeeParams(sotParams, 1, 100, 400);

        // 2. Insufficient Fee Min
        vm.expectRevert(SOTParams.SOTParams__validateFeeParams_insufficientFee.selector);
        sotParamsHelper.validateFeeParams(sotParams, 11, 100, 1000);

        // 3. Invalid Fee Max
        sotParams.feeMaxToken0 = 1e4;
        vm.expectRevert(SOTParams.SOTParams__validateFeeParams_invalidFeeMax.selector);
        sotParamsHelper.validateFeeParams(sotParams, 1, 100, 1000);

        // 4. Invalid Fee Min
        sotParams.feeMaxToken0 = 1e2;
        sotParams.feeMinToken0 = 1e2 + 1;

        vm.expectRevert(SOTParams.SOTParams__validateFeeParams_invalidFeeMin.selector);
        sotParamsHelper.validateFeeParams(sotParams, 1, 100, 1000);
    }


    function test_validatePriceConsistency() public {

        sotParamsHelper.setState(0, 100, 1, 1000);

        // more than 20%
        uint160 solverPrice = 121;
        uint160 newPrice = 100;
        vm.expectRevert(SOTParams.SOTParams__validatePriceBounds_solverAndSpotPriceNewExcessiveDeviation.selector);
        sotParamsHelper.validatePriceConsistency(
            solverPrice,
            newPrice,
            100,
            2000,
            2000
        );

        solverPrice = 101;
        uint160 oraclePrice = 126;
        vm.expectRevert(SOTParams.SOTParams__validatePriceBounds_spotAndOraclePricesExcessiveDeviation.selector);
        sotParamsHelper.validatePriceConsistency(
            solverPrice,
            newPrice,
            oraclePrice,
            2000,
            2000
        );

        oraclePrice = 120;
        newPrice = 95;
        vm.expectRevert(SOTParams.SOTParams__validatePriceBounds_newSpotAndOraclePricesExcessiveDeviation.selector);
        sotParamsHelper.validatePriceConsistency(
            solverPrice,
            newPrice,
            oraclePrice,
            2000,
            2000
        );

        oraclePrice = 120;
        newPrice = 100;

        sotParamsHelper.validatePriceConsistency(
            solverPrice,
            newPrice,
            oraclePrice,
            2000,
            2000  
        );
    }

    function test_validatePriceBounds() public {
        uint160 priceLow = 10;
        uint160 priceHigh = 1000;

        uint160 price = 5;

        vm.expectRevert(SOTParams.SOTParams__validatePriceBounds_newSpotPriceOutOfBounds.selector);
        sotParamsHelper.validatePriceBounds(price, priceLow, priceHigh);

        price = 2000;

        vm.expectRevert(SOTParams.SOTParams__validatePriceBounds_newSpotPriceOutOfBounds.selector);
        sotParamsHelper.validatePriceBounds(price, priceLow, priceHigh);

        price = 11;
        sotParamsHelper.validatePriceBounds(price, priceLow, priceHigh);
    }

    function test_hashParams() public {

        SolverOrderType memory sotParams;

        bytes32 expectedHash = keccak256(abi.encode(SOTConstants.SOT_TYPEHASH, sotParams));

        assertEq(expectedHash, sotParamsHelper.hashParams(sotParams));
    }

}
