// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import { Math } from '../../lib/valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { ALMLiquidityQuoteInput } from '../../lib/valantis-core/src/alm/interfaces/ISovereignALM.sol';

import { HybridOrderType, AMMState } from '../structs/HOTStructs.sol';
import { TightPack } from '../libraries/utils/TightPack.sol';
import { AlternatingNonceBitmap } from '../libraries/AlternatingNonceBitmap.sol';
import { HOTConstants } from '../libraries/HOTConstants.sol';

/**
    @notice Library for validating all parameters of a signed Hybrid Order Type (HOT) quote.
 */
library HOTParams {
    using TightPack for AMMState;
    using AlternatingNonceBitmap for uint56;

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error HOTParams__validateBasicParams_excessiveTokenInAmount();
    error HOTParams__validateBasicParams_excessiveTokenOutAmountRequested();
    error HOTParams__validateBasicParams_excessiveExpiryTime();
    error HOTParams__validateBasicParams_incorrectSwapDirection();
    error HOTParams__validateBasicParams_replayedQuote();
    error HOTParams__validateBasicParams_quoteExpired();
    error HOTParams__validateBasicParams_unauthorizedSender();
    error HOTParams__validateBasicParams_unauthorizedRecipient();
    error HOTParams__validateBasicParams_invalidSignatureTimestamp();
    error HOTParams__validateFeeParams_insufficientFee();
    error HOTParams__validateFeeParams_invalidfeeGrowthE6();
    error HOTParams__validateFeeParams_invalidFeeMax();
    error HOTParams__validateFeeParams_invalidFeeMin();
    error HOTParams__validatePriceBounds_invalidPriceBounds();
    error HOTParams__validatePriceBounds_newSpotPriceOutOfBounds();
    error HOTParams__validatePriceConsistency_newSpotAndOraclePricesExcessiveDeviation();
    error HOTParams__validatePriceConsistency_hotAndSpotPriceNewExcessiveDeviation();
    error HOTParams__validatePriceConsistency_spotAndOraclePricesExcessiveDeviation();

    /************************************************
     *  FUNCTIONS
     ***********************************************/

    function validateBasicParams(
        HybridOrderType memory hot,
        ALMLiquidityQuoteInput memory almLiquidityQuoteInput,
        uint256 amountOut,
        uint256 tokenOutMaxBound,
        uint32 maxDelay,
        uint56 alternatingNonceBitmap
    ) internal view {
        if (hot.isZeroToOne != almLiquidityQuoteInput.isZeroToOne)
            revert HOTParams__validateBasicParams_incorrectSwapDirection();

        if (hot.authorizedSender != almLiquidityQuoteInput.sender)
            revert HOTParams__validateBasicParams_unauthorizedSender();

        if (hot.authorizedRecipient != almLiquidityQuoteInput.recipient)
            revert HOTParams__validateBasicParams_unauthorizedRecipient();

        if (almLiquidityQuoteInput.amountInMinusFee > hot.amountInMax)
            revert HOTParams__validateBasicParams_excessiveTokenInAmount();

        if (hot.expiry > maxDelay) revert HOTParams__validateBasicParams_excessiveExpiryTime();

        if (hot.signatureTimestamp > block.timestamp) revert HOTParams__validateBasicParams_invalidSignatureTimestamp();

        // Also equivalent to: signatureTimestamp >= block.timestamp - maxDelay
        // So, block.timestamp - maxDelay <= signatureTimestamp <= block.timestamp
        if (block.timestamp > hot.signatureTimestamp + hot.expiry) revert HOTParams__validateBasicParams_quoteExpired();

        if (amountOut > tokenOutMaxBound) revert HOTParams__validateBasicParams_excessiveTokenOutAmountRequested();

        if (!alternatingNonceBitmap.checkNonce(hot.nonce, hot.expectedFlag)) {
            revert HOTParams__validateBasicParams_replayedQuote();
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
            revert HOTParams__validateFeeParams_insufficientFee();

        if (
            feeGrowthE6Token0 < feeGrowthE6MinBound ||
            feeGrowthE6Token1 < feeGrowthE6MinBound ||
            feeGrowthE6Token0 > feeGrowthE6MaxBound ||
            feeGrowthE6Token1 > feeGrowthE6MaxBound
        ) {
            revert HOTParams__validateFeeParams_invalidfeeGrowthE6();
        }

        // feeMax should be strictly less than 50% of total amountIn.
        // Note: A fee of 10_000 bips represents that for X amountIn swapped, we will charge X fee.
        // So, if amountIn = A, and feeBips = 100%, then amountInMinusFee = A/2, and effectiveFee = A/2.
        if (feeMaxToken0 >= HOTConstants.BIPS || feeMaxToken1 >= HOTConstants.BIPS)
            revert HOTParams__validateFeeParams_invalidFeeMax();

        if (feeMinToken0 > feeMaxToken0 || feeMinToken1 > feeMaxToken1)
            revert HOTParams__validateFeeParams_invalidFeeMin();
    }

    function validatePriceConsistency(
        AMMState storage ammState,
        uint160 sqrtHotPriceX96,
        uint160 sqrtSpotPriceNewX96,
        uint160 sqrtOraclePriceX96,
        uint256 maxOracleDeviationBipsLower,
        uint256 maxOracleDeviationBipsUpper,
        uint256 hotMaxDiscountBipsLower,
        uint256 hotMaxDiscountBipsUpper
    ) internal view {
        // Cache sqrt spot price, lower bound, and upper bound
        (uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96) = ammState.getState();

        // sqrt hot and new AMM spot price cannot differ beyond allowed bounds
        if (
            !checkPriceDeviation(sqrtHotPriceX96, sqrtSpotPriceNewX96, hotMaxDiscountBipsLower, hotMaxDiscountBipsUpper)
        ) {
            revert HOTParams__validatePriceConsistency_hotAndSpotPriceNewExcessiveDeviation();
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
            revert HOTParams__validatePriceConsistency_spotAndOraclePricesExcessiveDeviation();
        }

        // New AMM sqrt spot price (provided by HOT quote) and oracle sqrt price cannot differ
        // beyond allowed bounds
        if (
            !checkPriceDeviation(
                sqrtSpotPriceNewX96,
                sqrtOraclePriceX96,
                maxOracleDeviationBipsLower,
                maxOracleDeviationBipsUpper
            )
        ) {
            revert HOTParams__validatePriceConsistency_newSpotAndOraclePricesExcessiveDeviation();
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
            sqrtPriceLowX96 < HOTConstants.MIN_SQRT_PRICE ||
            sqrtPriceHighX96 > HOTConstants.MAX_SQRT_PRICE
        ) {
            revert HOTParams__validatePriceBounds_invalidPriceBounds();
        }

        // sqrt spot price cannot exceed or equal lower/upper AMM position's bounds
        if (sqrtSpotPriceX96 <= sqrtPriceLowX96 || sqrtSpotPriceX96 >= sqrtPriceHighX96) {
            revert HOTParams__validatePriceBounds_newSpotPriceOutOfBounds();
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

        if (diff * HOTConstants.BIPS > maxDeviationInBips * sqrtPriceBX96) {
            return false;
        }
        return true;
    }

    function hashParams(HybridOrderType memory hot) internal pure returns (bytes32) {
        return keccak256(abi.encode(HOTConstants.HOT_TYPEHASH, hot));
    }
}
