// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

struct SolverOrderType {
    uint256 amountInMax;
    uint256 amountOutMax;
    uint256 spotPriceX128;
    uint256 expectedOraclePriceX128;
    uint32 signatureTimestamp;
    uint32 expiry;
    address authorizedSender;
    uint16 feeMin;
    uint16 feeMax;
    uint16 feeGrowth;
}
