// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SolverOrderType } from 'src/structs/SOTStructs.sol';

library SOTParams {
    error SOTParams__validateBasicParams_excessiveTokenInAmount();
    error SOTParams__validateBasicParams_excessiveTokenOutAmountRequested();
    error SOTParams__validateBasicParams_invalidSignatureTimestamp();
    error SOTParams__validateBasicParams_quoteAlreadyProcessed();
    error SOTParams__validateBasicParams_quoteExpired();
    error SOTParams__validateBasicParams_unauthorizedSender();
    error SOTParams__validateFeeParams_insufficientFee();
    error SOTParams__validateFeeParams_invalidFeeGrowth();
    error SOTParams__validateFeeParams_invalidFeeMax();
    error SOTParams__validateFeeParams_invalidFeeMin();

    function validateBasicParams(
        address authorizedSender,
        uint256 amountInMax,
        uint256 amountOutMax,
        uint32 signatureTimestamp,
        uint32 expiry,
        uint256 amountIn,
        uint256 tokenOutMaxBound,
        uint32 lastProcessedBlockTimestamp,
        uint32 lastProcessedSignatureTimestamp
    ) internal view {
        if (authorizedSender != msg.sender) revert SOTParams__validateBasicParams_unauthorizedSender();

        if (amountIn > amountInMax) revert SOTParams__validateBasicParams_excessiveTokenInAmount();

        if (block.timestamp == lastProcessedBlockTimestamp) {
            revert SOTParams__validateBasicParams_quoteAlreadyProcessed();
        }

        if (signatureTimestamp <= lastProcessedSignatureTimestamp) {
            revert SOTParams__validateBasicParams_invalidSignatureTimestamp();
        }

        if (block.timestamp > signatureTimestamp + expiry) revert SOTParams__validateBasicParams_quoteExpired();

        if (amountOutMax > tokenOutMaxBound) revert SOTParams__validateBasicParams_excessiveTokenOutAmountRequested();
    }

    function validateFeeParams(
        uint16 feeMin,
        uint16 feeGrowth,
        uint16 feeMax,
        uint16 feeMinBound,
        uint16 feeGrowthMinBound,
        uint16 feeGrowthMaxBound
    ) internal pure {
        if (feeMin < feeMinBound) revert SOTParams__validateFeeParams_insufficientFee();

        if (feeGrowth < feeGrowthMinBound || feeGrowth > feeGrowthMaxBound)
            revert SOTParams__validateFeeParams_invalidFeeGrowth();

        if (feeMin > feeMax || feeMin > 10_000) revert SOTParams__validateFeeParams_invalidFeeMin();

        if (feeMax > 10_000) revert SOTParams__validateFeeParams_invalidFeeMax();
    }
}
