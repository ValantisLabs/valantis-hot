// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';
import { console } from 'forge-std/console.sol';

import { SOTParams } from 'src/libraries/SOTParams.sol';
import { SolverOrderType } from 'src/structs/SOTStructs.sol';

import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

contract TestSOTParams is Test {
    using SafeCast for uint256;

    // Default Contract Storage
    uint256 tokenOutMaxBound = 1000e18;
    uint32 maxDelay = 36; // 3 Blocks
    uint64 alternatingNonceBitmap = 2; // 0b10

    function _getSensibleSOTParams() internal returns (SolverOrderType memory sotParams) {
        // Sensible Defaults
        sotParams = SolverOrderType({
            amountInMax: 100e18,
            solverPriceX192Discounted: 1980 << 192, // 1% discount to first solver
            solverPriceX192Base: 2000 << 192,
            sqrtSpotPriceX96New: 45 << 96, // AMM spot price 2025
            authorizedSender: msg.sender,
            authorizedRecipient: makeAddr('RECIPIENT'),
            signatureTimestamp: (block.timestamp).toUint32(),
            expiry: 24, // 2 Blocks
            feeMin: 10,
            feeMax: 100,
            feeGrowth: 5,
            nonce: 1,
            expectedFlag: 1
        });
    }

    function setUp() public {
        vm.warp(1e6);
    }

    function test_validateBasicParams() public {
        // Correct Case
        SOTParams.validateBasicParams({
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
        SOTParams.validateBasicParams({
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
        SOTParams.validateBasicParams({
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
        SOTParams.validateBasicParams({
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
        SOTParams.validateBasicParams({
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
        SOTParams.validateBasicParams({
            sot: sotParams,
            amountOut: 500e18,
            recipient: makeAddr('RECIPIENT'),
            amountIn: 101e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });

        vm.expectRevert(SOTParams.SOTParams__validateBasicParams_excessiveTokenInAmount.selector);
        SOTParams.validateBasicParams({
            sot: sotParams,
            amountOut: 501e18,
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
        SOTParams.validateBasicParams({
            sot: sotParams,
            amountOut: 500e18,
            recipient: makeAddr('RECIPIENT'),
            amountIn: 100e18,
            tokenOutMaxBound: tokenOutMaxBound,
            maxDelay: maxDelay,
            alternatingNonceBitmap: alternatingNonceBitmap
        });
    }
}
