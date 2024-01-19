// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

library AlternatingNonceBitmap {
    using SafeCast for uint256;

    error AlternatingNonceBitmap__checkNonce_nonceOutOfBounds();
    error AlternatingNonceBitmap__checkNonce_expectedFlagInvalid();
    error AlternatingNonceBitmap__flipNonce_nonceOutOfBounds();

    function checkNonce(uint64 bitmap, uint8 nonce, uint8 expectedFlag) internal pure returns (bool) {
        if (nonce >= 64) revert AlternatingNonceBitmap__checkNonce_nonceOutOfBounds();
        if (expectedFlag > 1) revert AlternatingNonceBitmap__checkNonce_expectedFlagInvalid();

        return ((bitmap & (1 << nonce)) >> nonce) == expectedFlag;
    }

    function flipNonce(uint64 bitmap, uint8 nonce) internal pure returns (uint64) {
        if (nonce >= 64) revert AlternatingNonceBitmap__flipNonce_nonceOutOfBounds();

        return (bitmap ^ (1 << nonce)).toUint64();
    }
}
