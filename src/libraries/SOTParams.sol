// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// import 'forge-std/console.sol';

import { SolverOrderType } from 'src/structs/SOTStructs.sol';
import { TightPack } from 'src/libraries/utils/TightPack.sol';
import { AlternatingNonceBitmap } from 'src/libraries/AlternatingNonceBitmap.sol';
import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { SOTConstants } from 'src/libraries/SOTConstants.sol';

library SOTParams {
    using TightPack for TightPack.PackedState;
    using AlternatingNonceBitmap for uint56;

    error SOTParams__validateBasicParams_excessiveTokenInAmount();
    error SOTParams__validateBasicParams_excessiveTokenOutAmountRequested();
    error SOTParams__validateBasicParams_excessiveExpiryTime();
    error SOTParams__validateBasicParams_replayedQuote();
    error SOTParams__validateBasicParams_quoteExpired();
    error SOTParams__validateBasicParams_unauthorizedSender();
    error SOTParams__validateBasicParams_unauthorizedRecipient();
    error SOTParams__validateFeeParams_insufficientFee();
    error SOTParams__validateFeeParams_invalidFeeGrowth();
    error SOTParams__validateFeeParams_invalidFeeMax();
    error SOTParams__validateFeeParams_invalidFeeMin();
    error SOTParams__validatePriceBounds_newSpotAndOraclePricesExcessiveDeviation();
    error SOTParams__validatePriceBounds_newSpotPriceOutOfBounds();
    error SOTParams__validatePriceBounds_solverAndSpotPriceNewExcessiveDeviation();
    error SOTParams__validatePriceBounds_spotAndOraclePricesExcessiveDeviation();

    function validateBasicParams(
        SolverOrderType memory sot,
        uint256 amountOut,
        address sender,
        address recipient,
        uint256 amountIn,
        uint256 tokenOutMaxBound,
        uint32 maxDelay,
        uint56 alternatingNonceBitmap
    ) public view {
        if (sot.authorizedSender != sender) revert SOTParams__validateBasicParams_unauthorizedSender();

        if (sot.authorizedRecipient != recipient) revert SOTParams__validateBasicParams_unauthorizedRecipient();

        if (amountIn > sot.amountInMax) revert SOTParams__validateBasicParams_excessiveTokenInAmount();

        if (sot.expiry > maxDelay) revert SOTParams__validateBasicParams_excessiveExpiryTime();

        if (block.timestamp > sot.signatureTimestamp + sot.expiry) revert SOTParams__validateBasicParams_quoteExpired();

        if (amountOut > tokenOutMaxBound) revert SOTParams__validateBasicParams_excessiveTokenOutAmountRequested();

        if (!alternatingNonceBitmap.checkNonce(sot.nonce, sot.expectedFlag)) {
            revert SOTParams__validateBasicParams_replayedQuote();
        }
    }

    function validateFeeParams(
        SolverOrderType memory sot,
        uint16 feeMinBound,
        uint16 feeGrowthMinBound,
        uint16 feeGrowthMaxBound
    ) public pure {
        if (sot.feeMinToken0 < feeMinBound || sot.feeMinToken1 < feeMinBound)
            revert SOTParams__validateFeeParams_insufficientFee();

        if (
            sot.feeGrowthToken0 < feeGrowthMinBound ||
            sot.feeGrowthToken1 < feeGrowthMinBound ||
            sot.feeGrowthToken0 > feeGrowthMaxBound ||
            sot.feeGrowthToken1 > feeGrowthMaxBound
        ) {
            revert SOTParams__validateFeeParams_invalidFeeGrowth();
        }

        // feeMax should be strictly less than 100%
        if (sot.feeMaxToken0 >= SOTConstants.BIPS || sot.feeMaxToken1 >= SOTConstants.BIPS)
            revert SOTParams__validateFeeParams_invalidFeeMax();

        if (sot.feeMinToken0 > sot.feeMaxToken0 || sot.feeMinToken1 > sot.feeMaxToken1)
            revert SOTParams__validateFeeParams_invalidFeeMin();
    }

    function validatePriceConsistency(
        TightPack.PackedState storage ammState,
        uint160 sqrtSolverPriceX96,
        uint160 sqrtSpotPriceNewX96,
        uint160 sqrtOraclePriceX96,
        uint256 oraclePriceMaxDiffBips,
        uint256 solverMaxDiscountBips
    ) public view {
        // Cache sqrt spot price, lower bound, and upper bound
        (, uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96) = ammState.unpackState();

        // console.log('SOTParams.validatePriceConsistency: sqrtPriceX96Cache = ', sqrtSpotPriceX96);
        // console.log('SOTParams.validatePriceConsistency: sqrtPriceLowX96Cache = ', sqrtPriceLowX96);
        // console.log('SOTParams.validatePriceConsistency: sqrtPriceHighX96Cache = ', sqrtPriceHighX96);
        // console.log('SOTParams.validatePriceConsistency: sqrtSpotPriceNewX96 = ', sqrtSpotPriceNewX96);

        // sqrt solver and new AMM spot price cannot differ beyond allowed bounds
        uint256 solverAndSpotPriceNewAbsDiff = sqrtSolverPriceX96 > sqrtSpotPriceNewX96
            ? sqrtSolverPriceX96 - sqrtSpotPriceNewX96
            : sqrtSpotPriceNewX96 - sqrtSolverPriceX96;

        if (solverAndSpotPriceNewAbsDiff * SOTConstants.BIPS > solverMaxDiscountBips * sqrtSpotPriceNewX96) {
            revert SOTParams__validatePriceBounds_solverAndSpotPriceNewExcessiveDeviation();
        }

        // Current AMM sqrt spot price and oracle sqrt price cannot differ beyond allowed bounds
        uint256 spotPriceAndOracleAbsDiff = sqrtSpotPriceX96 > sqrtOraclePriceX96
            ? sqrtSpotPriceX96 - sqrtOraclePriceX96
            : sqrtOraclePriceX96 - sqrtSpotPriceX96;

        if (spotPriceAndOracleAbsDiff * SOTConstants.BIPS > oraclePriceMaxDiffBips * sqrtOraclePriceX96) {
            revert SOTParams__validatePriceBounds_spotAndOraclePricesExcessiveDeviation();
        }

        // New AMM sqrt spot price (provided by SOT quote) and oracle sqrt price cannot differ
        // beyond allowed bounds
        uint256 spotPriceNewAndOracleAbsDiff = sqrtSpotPriceNewX96 > sqrtOraclePriceX96
            ? sqrtSpotPriceNewX96 - sqrtOraclePriceX96
            : sqrtOraclePriceX96 - sqrtSpotPriceNewX96;

        if (spotPriceNewAndOracleAbsDiff * SOTConstants.BIPS > oraclePriceMaxDiffBips * sqrtOraclePriceX96) {
            revert SOTParams__validatePriceBounds_newSpotAndOraclePricesExcessiveDeviation();
        }

        validatePriceBounds(sqrtSpotPriceNewX96, sqrtPriceLowX96, sqrtPriceHighX96);
    }

    function validatePriceBounds(
        uint160 sqrtSpotPriceX96,
        uint160 sqrtPriceLowX96,
        uint160 sqrtPriceHighX96
    ) public pure {
        // sqrt spot price cannot exceed lower nor upper AMM position's bounds
        if (sqrtSpotPriceX96 < sqrtPriceLowX96 || sqrtSpotPriceX96 > sqrtPriceHighX96) {
            revert SOTParams__validatePriceBounds_newSpotPriceOutOfBounds();
        }
    }

    function hashParams(SolverOrderType memory sot) public pure returns (bytes32) {
        return keccak256(abi.encode(SOTConstants.SOT_TYPEHASH, sot));
    }
}
