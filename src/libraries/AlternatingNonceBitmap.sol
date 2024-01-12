// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

library AlternatingNonceBitmap {
    using SafeCast for uint256;

    function checkNonce(uint64 bitmap, uint8 nonce, uint8 expectedFlag) internal pure returns (bool) {
        require(nonce < 64, 'ANB: nonce out of bounds');
        require(expectedFlag == 0 || expectedFlag == 1, 'ANB: expectedFlag must be 0 or 1');

        return ((bitmap & (1 << nonce)) >> nonce) == expectedFlag;
    }

    function flipNonce(uint64 bitmap, uint8 nonce) internal pure returns (uint64) {
        require(nonce < 64, 'ANB: nonce out of bounds');

        return (bitmap ^ (1 << nonce)).toUint64();
    }
}
