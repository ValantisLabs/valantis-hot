// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

/**
    @notice The struct with all the information for a solver swap. 
    This struct is signed by the signer, and passed on to solvers who put it onchain for a SOT Swap.
 */
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
    uint16 feeGrowthInPipsToken0;
    uint16 feeMinToken1;
    uint16 feeMaxToken1;
    uint16 feeGrowthInPipsToken1;
    uint8 nonce;
    uint8 expectedFlag;
}

/**
    @notice Packed struct containing state variables which get updated on solver swaps.
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
struct SolverWriteSlot {
    uint8 lastProcessedBlockQuoteCount;
    uint16 feeGrowthInPipsToken0;
    uint16 feeMaxToken0;
    uint16 feeMinToken0;
    uint16 feeGrowthInPipsToken1;
    uint16 feeMaxToken1;
    uint16 feeMinToken1;
    uint32 lastStateUpdateTimestamp;
    uint32 lastProcessedQuoteTimestamp;
    uint32 lastProcessedSignatureTimestamp;
    uint56 alternatingNonceBitmap;
}

/**
    @notice Contains all the information that a solver needs to read while executing a swap.
            *maxAllowedQuotes:
                Maximum number of quotes that can be processed in a single block.

            *solverFeeBipsToken0:
                Fee in basis points for all subsequent solvers for token0.

            *solverFeeBipsToken1:
                Fee in basis points for all subsequent solvers for token1.

            *signer:
                Address of the signer of the SOT.
 */
struct SolverReadSlot {
    uint8 maxAllowedQuotes;
    uint16 solverFeeBipsToken0;
    uint16 solverFeeBipsToken1;
    address signer;
}

/**
    @notice Contains all the arguments passed to the constructor of the SOT.
 */
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
    uint32 maxOracleUpdateDurationFeed0;
    uint32 maxOracleUpdateDurationFeed1;
    uint16 solverMaxDiscountBips;
    uint16 oraclePriceMaxDiffBips;
    uint16 minAmmFeeGrowthInPips;
    uint16 maxAmmFeeGrowthInPips;
    uint16 minAmmFee;
}

/**
    @notice Packed struct that contains all variables relevant to the state of the AMM.
        * flags (uint32):
            * bit 0: pause flag
        * a: sqrtSpotPriceX96
        * b: sqrtPriceLowX96
        * c: sqrtPriceHighX96
        
    This arrangement saves 1 storage slot by packing the variables at the bit level.
    
    @dev Should never be used directly without the help of the TightPack library.

    @dev slot1: << 32 flag bits | upper 64 bits of b | all 160 bits of a >>
         slot2: << lower 96 bits of b | all 160 bits of c >>
 */
struct AMMState {
    uint256 slot1;
    uint256 slot2;
}
