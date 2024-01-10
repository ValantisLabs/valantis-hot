// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

struct SolverOrderType {
    uint256 amountInMax;
    uint160 solverPriceX96Discounted; // Price for the first solver
    uint160 solverPriceX96Base; // Price for all subsequent solvers
    uint160 sqrtSpotPriceX96New;
    address authorizedSender;
    address authorizedRecipient;
    uint32 signatureTimestamp;
    uint32 expiry;
    uint16 feeMin;
    uint16 feeMax;
    uint16 feeGrowth;
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
struct SwapState {
    uint32 lastProcessedBlockTimestamp;
    uint32 lastProcessedSignatureTimestamp;
    uint16 lastProcessedFeeGrowth;
    uint16 lastProcessedFeeMin;
    uint16 lastProcessedFeeMax;
    uint16 solverFeeInBips;
}
