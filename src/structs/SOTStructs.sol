// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

struct SolverOrderType {
    uint256 amountInMax;
    uint256 solverPriceX192Discounted; // Price for the first solver
    uint256 solverPriceX192Base; // Price for all subsequent solvers
    uint160 sqrtSpotPriceX96New;
    address authorizedSender;
    address authorizedRecipient;
    uint32 signatureTimestamp;
    uint32 expiry;
    uint16 feeMinToken0;
    uint16 feeMaxToken0;
    uint16 feeGrowthToken0;
    uint16 feeMinToken1;
    uint16 feeMaxToken1;
    uint16 feeGrowthToken1;
    uint8 nonce;
    uint8 expectedFlag;
}

/**
    @notice Packed struct containing state variables which get updated on swaps:
            *lastProcessedBlockTimestamp:
                Block timestamp of the last Solver Order Type which has been successfully processed.

            *lastProcessedSignatureTimestamp:
                Signature timestamp of the last Solver Order Type which has been successfully processed.

            *lastProcessedFeeGrowth:
                Fee Growth according to the last Solver Order Type which has been successfully processed.
		        Must be within the bounds of min and max fee growth immutables.

            *lastProcessedFeeMin:
                Minimum AMM fee according to the last Solver Order Type which has been successfully processed.

            *lastProcessedFeeMax:
                Maximum AMM fee according to the last Solver Order Type which has been successfully processed.
 */
// Slot Packed
struct SolverWriteSlot {
    uint8 lastProcessedBlockQuoteCount;
    uint16 feeGrowthToken0;
    uint16 feeMaxToken0;
    uint16 feeMinToken0;
    uint16 feeGrowthToken1;
    uint16 feeMaxToken1;
    uint16 feeMinToken1;
    uint32 lastStateUpdateTimestamp;
    uint32 lastProcessedQuoteTimestamp;
    uint32 lastProcessedSignatureTimestamp;
    uint56 alternatingNonceBitmap;
}

struct SolverReadSlot {
    uint8 maxAllowedQuotes;
    uint16 solverFeeBipsToken0;
    uint16 solverFeeBipsToken1;
    address signer;
}

struct SOTConstructorArgs {
    address pool;
    address manager;
    address signer;
    address liquidityProvider;
    address feedToken0;
    address feedToken1;
    uint160 sqrtSpotPriceX96;
    uint160 sqrtPriceLowX96;
    uint160 sqrtPriceHighX96;
    uint32 maxDelay;
    uint32 maxOracleUpdateDuration;
    uint16 solverMaxDiscountBips;
    uint16 oraclePriceMaxDiffBips;
    uint16 minAmmFeeGrowth;
    uint16 maxAmmFeeGrowth;
    uint16 minAmmFee;
}
