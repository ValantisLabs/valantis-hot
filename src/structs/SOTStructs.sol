// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

/**
    @notice The struct with all the information for a solver swap. 

    This struct is signed by `signer`, and put onchain by solvers via SOT swaps.

    * amountInMax: Maximum amount of input token which `authorizedSender` is allowed to swap.
    * sqrtSolverPriceX96Discounted: sqrtPriceX96 to quote if the SOT is eligible to update AMM state (see SOT).
    * sqrtSolverPriceX96Base: sqrtPriceX96 to quote if the SOT isn't eligible to update AMM (can be same as above).
    * sqrtSpotPriceX96New: New sqrt spot price of the AMM, in Q96 format.
    * authorizedSender: Address of authorized msg.sender in `pool`.
    * authorizedRecipient: Address of authorized recipient of tokenOut amounts.
    * signatureTimestamp: Offchain UNIX timestamp that determines when this SOT intent has been signed.
    * expiry: Duration, in seconds, for the validity of this SOT intent.
    * feeMinToken0: Minimum AMM swap fee for token0.
    * feeMaxToken0: Maximum AMM swap fee for token0.
    * feeGrowthE6Token0: Fee growth in pips, per second, of AMM swap fee for token0.
    * feeMinToken1: Minimum AMM swap fee for token1.
    * feeMaxToken1: Maximum AMM swap fee for token1.
    * feeGrowthE6Token1: Fee growth in pips, per second, of AMM swap fee for token1.
    * nonce: Nonce in bitmap format (see AlternatingNonceBitmap library and docs).
    * expectedFlag: Expected flag (0 or 1) for nonce (see AlternatingNonceBitmap library and docs).
    * isZeroToOne: Direction of the swap for which the SOT is valid.
 */
struct SolverOrderType {
    uint256 amountInMax;
    uint160 sqrtSolverPriceX96Discounted;
    uint160 sqrtSolverPriceX96Base;
    uint160 sqrtSpotPriceX96New;
    address authorizedSender;
    address authorizedRecipient;
    uint32 signatureTimestamp;
    uint32 expiry;
    uint16 feeMinToken0;
    uint16 feeMaxToken0;
    uint16 feeGrowthE6Token0;
    uint16 feeMinToken1;
    uint16 feeMaxToken1;
    uint16 feeGrowthE6Token1;
    uint8 nonce;
    uint8 expectedFlag;
    bool isZeroToOne;
}

/**
    @notice Packed struct containing state variables which get updated on SOT swaps.

    * lastProcessedBlockQuoteCount: Number of SOT swaps processed in the last block.
    * feeGrowthE6Token0: Fee growth in pips, per second, of AMM swap fee for token0.
    * feeMaxToken0: Maximum AMM swap fee for token0.
    * feeMinToken0: Minimum AMM swap fee for token0.
    * feeGrowthE6Token1: Fee growth in pips, per second, of AMM swap fee for token1.
    * feeMaxToken1: Maximum AMM swap fee for token1.
    * feeMinToken1: Minimum AMM swap fee for token1.
    * lastStateUpdateTimestamp: Block timestamp of the last AMM state update from an SOT swap.
    * lastProcessedQuoteTimestamp: Block timestamp of the last processed SOT swap (not all SOT swaps update AMM state).
    * lastProcessedSignatureTimestamp: Signature timestamp of the last SOT swap which has been successfully processed.
    * alternatingNonceBitmap: Nonce bitmap (see AlternatingNonceBitmap library and docs).
 */
struct SolverWriteSlot {
    uint8 lastProcessedBlockQuoteCount;
    uint16 feeGrowthE6Token0;
    uint16 feeMaxToken0;
    uint16 feeMinToken0;
    uint16 feeGrowthE6Token1;
    uint16 feeMaxToken1;
    uint16 feeMinToken1;
    uint32 lastStateUpdateTimestamp;
    uint32 lastProcessedQuoteTimestamp;
    uint32 lastProcessedSignatureTimestamp;
    uint56 alternatingNonceBitmap;
}

/**
    @notice Contains read-only variables required during execution of an SOT swap.
    * isPaused: Indicates whether the contract is paused or not.     
    * maxAllowedQuotes: Maximum number of quotes that can be processed in a single block.
    * maxOracleDeviationBipsLower: Maximum deviation in bips allowed when, sqrtSpotPrice < sqrtOraclePrice
    * maxOracleDeviationBipsUpper: Maximum deviation in bips allowed when, sqrtSpotPrice >= sqrtOraclePrice
    * solverFeeBipsToken0: Fee in basis points for all subsequent solvers for token0.
    * solverFeeBipsToken1: Fee in basis points for all subsequent solvers for token1.
    * signer: Address of the signer of the SOT.
 */
struct SolverReadSlot {
    bool isPaused;
    uint8 maxAllowedQuotes;
    uint16 maxOracleDeviationBipsLower;
    uint16 maxOracleDeviationBipsUpper;
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
    uint16 solverMaxDiscountBipsLower;
    uint16 solverMaxDiscountBipsUpper;
    uint16 maxOracleDeviationBound;
    uint16 minAMMFeeGrowthE6;
    uint16 maxAMMFeeGrowthE6;
    uint16 minAMMFee;
}

/**
    @notice Packed struct that contains all variables relevant to the state of the AMM.
    
    * a: sqrtSpotPriceX96
    * b: sqrtPriceLowX96
    * c: sqrtPriceHighX96
        
    This arrangement saves 1 storage slot by packing the variables at the bit level.
    
    @dev Should never be used directly without the help of the TightPack library.

    @dev slot1: << 32 free bits | upper 64 bits of b | all 160 bits of a >>
         slot2: << lower 96 bits of b | all 160 bits of c >>
 */
struct AMMState {
    uint256 slot1;
    uint256 slot2;
}
