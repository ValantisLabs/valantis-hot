// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SolverOrderType } from 'src/structs/SOTStructs.sol';
import { TightPack } from 'src/libraries/utils/TightPack.sol';

library SOTParams {
    using TightPack for TightPack.PackedState;

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
        // TODO: Might need to use tx.origin to authenticate solvers,
        // since CowSwap contract will be msg.sender to the pool
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

        if (feeGrowth < feeGrowthMinBound || feeGrowth > feeGrowthMaxBound) {
            revert SOTParams__validateFeeParams_invalidFeeGrowth();
        }

        if (feeMin > feeMax || feeMin > 10_000) revert SOTParams__validateFeeParams_invalidFeeMin();

        if (feeMax > 10_000) revert SOTParams__validateFeeParams_invalidFeeMax();
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
