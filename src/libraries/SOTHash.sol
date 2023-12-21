// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SolverOrderType } from 'src/structs/SOTStructs.sol';

library SOTHash {
    bytes32 public constant SOT_TYPEHASH =
        keccak256(
            // solhint-disable-next-line max-line-length
            'SolverOrderType(uint256 amountInMax,uint256 amountOutMax,uint256 spotPriceX128,uint256 expectedOraclePriceX128,uint32 signatureTimestamp,uint32 expiry,address authorizedSender,uint16 feeMin,uint16 feeMax,uint16 feeGrowth)'
        );

    function hashStruct(SolverOrderType memory sot) internal pure returns (bytes32) {
        return keccak256(abi.encode(SOT_TYPEHASH, sot));
    }
}