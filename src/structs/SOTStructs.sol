// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

struct SolverOrderType {
    uint256 amountInMax;
    uint256 amountOutMax;
    uint160 sqrtSpotPriceX96New;
    uint32 signatureTimestamp;
    uint32 expiry;
    address authorizedSender;
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

            *managerFeeInBips:
                Manager fee charged on all volume in basis points

            *unclaimedManagerFeeToken0:
                Unclaimed manager fee in token0 
            
            *unclaimedManagerFeeToken1:
                Unclaimed manager fee in token1
 */
struct SwapState {
    uint32 lastProcessedBlockTimestamp;
    uint32 lastProcessedSignatureTimestamp;
    uint16 lastProcessedFeeGrowth;
    uint16 lastProcessedFeeMin;
    uint16 lastProcessedFeeMax;
    uint16 managerFeeInBips;
    uint64 unclaimedManagerFeeToken0;
    uint64 unclaimedManagerFeeToken1;
}
