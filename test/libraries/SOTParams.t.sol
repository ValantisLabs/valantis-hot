// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';
import { console } from 'forge-std/console.sol';

import { SOTParams } from 'src/libraries/SOTParams.sol';
import { SOTParamsHelper } from 'test/helpers/SOTParamsHelper.sol';
import { SolverOrderType } from 'src/structs/SOTStructs.sol';
import { SOTBase } from 'test/base/SOTBase.t.sol';

import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

contract TestSOTParams is SOTBase {
    using SafeCast for uint256;

    SOTParamsHelper sotParamsHelper;

    // Default Contract Storage
    uint256 public tokenOutMaxBound = 1000e18;
    uint32 public maxDelay = 36; // 3 Blocks
    uint64 public alternatingNonceBitmap = 2; // 0b10

    function setUp() public override {
        vm.warp(1e6);
        sotParamsHelper = new SOTParamsHelper();
    }

    function test_validateBasicParams() public {
        // Correct Case
        sotParamsHelper.validateBasicParams({
            sot: _getSensibleSOTParams(),
            amountOut: 500e18,
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
            recipient: makeAddr('WRONG_RECIPIENT'),
            amountIn: 100e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });

        // Incorrect Sender
        vm.expectRevert(SOTParams.SOTParams__validateBasicParams_unauthorizedSender.selector);
        vm.startPrank(makeAddr('WRONG_SENDER'));
        sotParamsHelper.validateBasicParams({
            sot: sotParams,
            amountOut: 500e18,
            recipient: makeAddr('RECIPIENT'),
            amountIn: 100e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });
        vm.stopPrank();
    }

    function test_validateBasicParams_excessiveTokenAmounts() public {
        SolverOrderType memory sotParams = _getSensibleSOTParams();

        vm.expectRevert(SOTParams.SOTParams__validateBasicParams_excessiveTokenInAmount.selector);
        sotParamsHelper.validateBasicParams({
            sot: sotParams,
            amountOut: 500e18,
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
        sotParamsHelper.validateFeeParams(sotParams, 1, 1, 10);

        // // Incorrect Cases
        // 1. Fee Growth out of min & max bounds
        vm.expectRevert(SOTParams.SOTParams__validateFeeParams_invalidFeeGrowth.selector);
        sotParamsHelper.validateFeeParams(sotParams, 1, 6, 10);

        vm.expectRevert(SOTParams.SOTParams__validateFeeParams_invalidFeeGrowth.selector);
        sotParamsHelper.validateFeeParams(sotParams, 1, 1, 4);

        // 2. Insufficient Fee Min
        vm.expectRevert(SOTParams.SOTParams__validateFeeParams_insufficientFee.selector);
        sotParamsHelper.validateFeeParams(sotParams, 11, 1, 10);

        // 3. Invalid Fee Max
        sotParams.feeMax = 1e4;
        vm.expectRevert(SOTParams.SOTParams__validateFeeParams_invalidFeeMax.selector);
        sotParamsHelper.validateFeeParams(sotParams, 1, 1, 10);

        // 4. Invalid Fee Min
        sotParams.feeMax = 1e2;
        sotParams.feeMin = 1e2 + 1;

        vm.expectRevert(SOTParams.SOTParams__validateFeeParams_invalidFeeMin.selector);
        sotParamsHelper.validateFeeParams(sotParams, 1, 1, 10);
    }
}
