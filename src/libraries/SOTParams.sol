// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SolverOrderType } from 'src/structs/SOTStructs.sol';
import { TightPack } from 'src/libraries/utils/TightPack.sol';
import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';

library SOTParams {
    using TightPack for TightPack.PackedState;

    error SOTParams__validateBasicParams_excessiveTokenInAmount();
    error SOTParams__validateBasicParams_excessiveTokenOutAmountRequested();
    // error SOTParams__validateBasicParams_invalidSignatureTimestamp();
    // error SOTParams__validateBasicParams_quoteAlreadyProcessed();
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

    /**
        @notice Min and max sqrt price bounds.
        @dev Same bounds as in https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickMath.sol.
     */
    uint160 public constant MIN_SQRT_PRICE = 4295128739;
    uint160 public constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;

    function validateBasicParams(
        SolverOrderType memory sot,
        uint160 solverPriceX96,
        address recipient,
        uint256 amountIn,
        uint256 tokenOutMaxBound // uint32 lastProcessedBlockTimestamp, // uint32 lastProcessedSignatureTimestamp
    ) internal view {
        if (sot.authorizedSender != msg.sender) revert SOTParams__validateBasicParams_unauthorizedSender();

        if (sot.authorizedRecipient != recipient) revert SOTParams__validateBasicParams_unauthorizedRecipient();

        if (amountIn > sot.amountInMax) revert SOTParams__validateBasicParams_excessiveTokenInAmount();

        // TODO: verify if removing these checks is safe for multiple quotes
        // TODO: check if any additional checks are needed for multiple quotes
        // if (block.timestamp == lastProcessedBlockTimestamp) {
        //     revert SOTParams__validateBasicParams_quoteAlreadyProcessed();
        // }

        // if (sot.signatureTimestamp <= lastProcessedSignatureTimestamp) {
        //     revert SOTParams__validateBasicParams_invalidSignatureTimestamp();
        // }

        if (block.timestamp > sot.signatureTimestamp + sot.expiry) revert SOTParams__validateBasicParams_quoteExpired();

        if (Math.mulDiv(amountIn, solverPriceX96, 2 ** 96) > tokenOutMaxBound)
            revert SOTParams__validateBasicParams_excessiveTokenOutAmountRequested();
    }

    // TODO: convert all constant value to constant variables in a separate contract
    function validateFeeParams(
        SolverOrderType memory sot,
        uint16 feeMinBound,
        uint16 feeGrowthMinBound,
        uint16 feeGrowthMaxBound
    ) internal pure {
        if (sot.feeMin < feeMinBound) revert SOTParams__validateFeeParams_insufficientFee();

        if (sot.feeGrowth < feeGrowthMinBound || sot.feeGrowth > feeGrowthMaxBound) {
            revert SOTParams__validateFeeParams_invalidFeeGrowth();
        }

        if (sot.feeMin > sot.feeMax || sot.feeMin > 10_000) revert SOTParams__validateFeeParams_invalidFeeMin();

        if (sot.feeMax > 10_000) revert SOTParams__validateFeeParams_invalidFeeMax();
    }

    function validatePriceBounds(
        TightPack.PackedState storage ammState,
        uint160 sqrtSolverPriceX96,
        uint160 sqrtSpotPriceNewX96,
        uint160 sqrtOraclePriceX96,
        uint256 oraclePriceMaxDiffBips,
        uint256 solverMaxDiscountBips
    ) internal view {
        // Cache sqrt spot price, lower bound, and upper bound
        (uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96) = ammState.unpackState();

        // sqrt solver and new AMM spot price cannot differ beyond allowed bounds
        uint256 solverAndSpotPriceNewAbsDiff = sqrtSolverPriceX96 > sqrtSpotPriceNewX96
            ? sqrtSolverPriceX96 - sqrtSpotPriceNewX96
            : sqrtSpotPriceNewX96 - sqrtSolverPriceX96;

        if (solverAndSpotPriceNewAbsDiff * 10_000 > solverMaxDiscountBips * sqrtSpotPriceNewX96) {
            revert SOTParams__validatePriceBounds_solverAndSpotPriceNewExcessiveDeviation();
        }

        // Current AMM sqrt spot price and oracle sqrt price cannot differ beyond allowed bounds
        uint256 spotPriceAndOracleAbsDiff = sqrtSpotPriceX96 > sqrtOraclePriceX96
            ? sqrtSpotPriceX96 - sqrtOraclePriceX96
            : sqrtOraclePriceX96 - sqrtSpotPriceX96;

        if (spotPriceAndOracleAbsDiff * 10_000 > oraclePriceMaxDiffBips * sqrtOraclePriceX96) {
            revert SOTParams__validatePriceBounds_spotAndOraclePricesExcessiveDeviation();
        }

        // New AMM sqrt spot price (provided by SOT quote) and oracle sqrt price cannot differ
        // beyond allowed bounds
        uint256 spotPriceNewAndOracleAbsDiff = sqrtSpotPriceNewX96 > sqrtOraclePriceX96
            ? sqrtSpotPriceNewX96 - sqrtOraclePriceX96
            : sqrtOraclePriceX96 - sqrtSpotPriceNewX96;

        if (spotPriceNewAndOracleAbsDiff * 10_000 > oraclePriceMaxDiffBips * sqrtOraclePriceX96) {
            revert SOTParams__validatePriceBounds_newSpotAndOraclePricesExcessiveDeviation();
        }

        // New AMM sqrt spot price cannot exceed lower nor upper AMM position's bounds
        if (sqrtSpotPriceNewX96 < sqrtPriceLowX96 || sqrtSpotPriceNewX96 > sqrtPriceHighX96) {
            revert SOTParams__validatePriceBounds_newSpotPriceOutOfBounds();
        }

        // TODO: double check if expectedOraclePrice check is needed
    }
}
