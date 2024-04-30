// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { console } from 'forge-std/console.sol';

import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';

import { SolverOrderType, AMMState } from 'src/structs/SOTStructs.sol';
import { TightPack } from 'src/libraries/utils/TightPack.sol';
import { AlternatingNonceBitmap } from 'src/libraries/AlternatingNonceBitmap.sol';
import { SOTConstants } from 'src/libraries/SOTConstants.sol';

/**
    @notice Library for validating all parameters of a signed Solver Rrder Type (SOT) quote.
 */
library SOTParams {
    using TightPack for AMMState;
    using AlternatingNonceBitmap for uint56;

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error SOTParams__validateBasicParams_excessiveTokenInAmount();
    error SOTParams__validateBasicParams_excessiveTokenOutAmountRequested();
    error SOTParams__validateBasicParams_excessiveExpiryTime();
    error SOTParams__validateBasicParams_incorrectSwapDirection();
    error SOTParams__validateBasicParams_replayedQuote();
    error SOTParams__validateBasicParams_quoteExpired();
    error SOTParams__validateBasicParams_unauthorizedSender();
    error SOTParams__validateBasicParams_unauthorizedRecipient();
    error SOTParams__validateBasicParams_invalidSignatureTimestamp();
    error SOTParams__validateFeeParams_insufficientFee();
    error SOTParams__validateFeeParams_invalidfeeGrowthE6();
    error SOTParams__validateFeeParams_invalidFeeMax();
    error SOTParams__validateFeeParams_invalidFeeMin();
    error SOTParams__validatePriceBounds_invalidPriceBounds();
    error SOTParams__validatePriceBounds_newSpotPriceOutOfBounds();
    error SOTParams__validatePriceConsistency_newSpotAndOraclePricesExcessiveDeviation();
    error SOTParams__validatePriceConsistency_solverAndSpotPriceNewExcessiveDeviation();
    error SOTParams__validatePriceConsistency_spotAndOraclePricesExcessiveDeviation();

    /************************************************
     *  FUNCTIONS
     ***********************************************/

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
    ) internal view {
        if (sot.isZeroToOne != isZeroToOne) revert SOTParams__validateBasicParams_incorrectSwapDirection();

        if (sot.authorizedSender != sender) revert SOTParams__validateBasicParams_unauthorizedSender();

        if (sot.authorizedRecipient != recipient) revert SOTParams__validateBasicParams_unauthorizedRecipient();

        if (amountIn > sot.amountInMax) revert SOTParams__validateBasicParams_excessiveTokenInAmount();

        if (sot.expiry > maxDelay) revert SOTParams__validateBasicParams_excessiveExpiryTime();

        if (sot.signatureTimestamp > block.timestamp) revert SOTParams__validateBasicParams_invalidSignatureTimestamp();

        // Also equivalent to: signatureTimestamp >= block.timestamp - maxDelay
        // So, block.timestamp - maxDelay <= signatureTimestamp <= block.timestamp
        if (block.timestamp > sot.signatureTimestamp + sot.expiry) revert SOTParams__validateBasicParams_quoteExpired();

        if (amountOut > tokenOutMaxBound) revert SOTParams__validateBasicParams_excessiveTokenOutAmountRequested();

        if (!alternatingNonceBitmap.checkNonce(sot.nonce, sot.expectedFlag)) {
            revert SOTParams__validateBasicParams_replayedQuote();
        }
    }

    function validateFeeParams(
        uint16 feeMinToken0,
        uint16 feeMaxToken0,
        uint16 feeGrowthE6Token0,
        uint16 feeMinToken1,
        uint16 feeMaxToken1,
        uint16 feeGrowthE6Token1,
        uint16 feeMinBound,
        uint16 feeGrowthE6MinBound,
        uint16 feeGrowthE6MaxBound
    ) internal pure {
        if (feeMinToken0 < feeMinBound || feeMinToken1 < feeMinBound)
            revert SOTParams__validateFeeParams_insufficientFee();

        if (
            feeGrowthE6Token0 < feeGrowthE6MinBound ||
            feeGrowthE6Token1 < feeGrowthE6MinBound ||
            feeGrowthE6Token0 > feeGrowthE6MaxBound ||
            feeGrowthE6Token1 > feeGrowthE6MaxBound
        ) {
            revert SOTParams__validateFeeParams_invalidfeeGrowthE6();
        }

        // feeMax should be strictly less than 50% of total amountIn.
        // Note: A fee of 10_000 bips represents that for X amountIn swapped, we will charge X fee.
        // So, if amountIn = A, and feeBips = 100%, then amountInMinusFee = A/2, and effectiveFee = A/2.
        if (feeMaxToken0 >= SOTConstants.BIPS || feeMaxToken1 >= SOTConstants.BIPS)
            revert SOTParams__validateFeeParams_invalidFeeMax();

        if (feeMinToken0 > feeMaxToken0 || feeMinToken1 > feeMaxToken1)
            revert SOTParams__validateFeeParams_invalidFeeMin();
    }

    function validatePriceConsistency(
        AMMState storage ammState,
        uint160 sqrtSolverPriceX96,
        uint160 sqrtSpotPriceNewX96,
        uint160 sqrtOraclePriceX96,
        uint256 maxOracleDeviationBipsLower,
        uint256 maxOracleDeviationBipsUpper,
        uint256 solverMaxDiscountBips
    ) internal view {
        console.log(sqrtSpotPriceNewX96);
        // Cache sqrt spot price, lower bound, and upper bound
        (uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96) = ammState.getState();

        console.log(sqrtPriceLowX96);
        console.log(sqrtPriceHighX96);

        // sqrt solver and new AMM spot price cannot differ beyond allowed bounds
        if (
            !checkPriceDeviation(sqrtSolverPriceX96, sqrtSpotPriceNewX96, solverMaxDiscountBips, solverMaxDiscountBips)
        ) {
            revert SOTParams__validatePriceConsistency_solverAndSpotPriceNewExcessiveDeviation();
        }

        // Current AMM sqrt spot price and oracle sqrt price cannot differ beyond allowed bounds
        if (
            !checkPriceDeviation(
                sqrtSpotPriceX96,
                sqrtOraclePriceX96,
                maxOracleDeviationBipsLower,
                maxOracleDeviationBipsUpper
            )
        ) {
            revert SOTParams__validatePriceConsistency_spotAndOraclePricesExcessiveDeviation();
        }

        // New AMM sqrt spot price (provided by SOT quote) and oracle sqrt price cannot differ
        // beyond allowed bounds
        if (
            !checkPriceDeviation(
                sqrtSpotPriceNewX96,
                sqrtOraclePriceX96,
                maxOracleDeviationBipsLower,
                maxOracleDeviationBipsUpper
            )
        ) {
            revert SOTParams__validatePriceConsistency_newSpotAndOraclePricesExcessiveDeviation();
        }

        validatePriceBounds(sqrtSpotPriceNewX96, sqrtPriceLowX96, sqrtPriceHighX96);
    }

    function validatePriceBounds(
        uint160 sqrtSpotPriceX96,
        uint160 sqrtPriceLowX96,
        uint160 sqrtPriceHighX96
    ) internal pure {
        // Check that lower bound is smaller than upper bound,
        // and price bounds are within the MAX and MIN sqrt prices
        if (
            sqrtPriceLowX96 >= sqrtPriceHighX96 ||
            sqrtPriceLowX96 < SOTConstants.MIN_SQRT_PRICE ||
            sqrtPriceHighX96 > SOTConstants.MAX_SQRT_PRICE
        ) {
            revert SOTParams__validatePriceBounds_invalidPriceBounds();
        }

        // sqrt spot price cannot exceed or equal lower/upper AMM position's bounds
        if (sqrtSpotPriceX96 <= sqrtPriceLowX96 || sqrtSpotPriceX96 >= sqrtPriceHighX96) {
            revert SOTParams__validatePriceBounds_newSpotPriceOutOfBounds();
        }
    }

    function checkPriceDeviation(
        uint256 sqrtPriceAX96,
        uint256 sqrtPriceBX96,
        uint256 maxDeviationInBipsLower,
        uint256 maxDeviationInBipsUpper
    ) internal pure returns (bool) {
        uint256 diff = sqrtPriceAX96 > sqrtPriceBX96 ? sqrtPriceAX96 - sqrtPriceBX96 : sqrtPriceBX96 - sqrtPriceAX96;
        uint256 maxDeviationInBips = sqrtPriceAX96 < sqrtPriceBX96 ? maxDeviationInBipsLower : maxDeviationInBipsUpper;

        if (diff * SOTConstants.BIPS > maxDeviationInBips * sqrtPriceBX96) {
            return false;
        }
        return true;
    }

    function hashParams(SolverOrderType memory sot) internal pure returns (bytes32) {
        return keccak256(abi.encode(SOTConstants.SOT_TYPEHASH, sot));
    }
}
