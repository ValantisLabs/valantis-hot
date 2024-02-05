// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

library AlternatingNonceBitmap {
    using SafeCast for uint256;

    error AlternatingNonceBitmap__checkNonce_nonceOutOfBounds();
    error AlternatingNonceBitmap__checkNonce_expectedFlagInvalid();
    error AlternatingNonceBitmap__flipNonce_nonceOutOfBounds();

    function checkNonce(uint56 bitmap, uint8 nonce, uint8 expectedFlag) internal pure returns (bool) {
        if (nonce >= 56) revert AlternatingNonceBitmap__checkNonce_nonceOutOfBounds();
        if (expectedFlag > 1) revert AlternatingNonceBitmap__checkNonce_expectedFlagInvalid();

        return ((bitmap & (1 << nonce)) >> nonce) == expectedFlag;
    }

    function flipNonce(uint56 bitmap, uint8 nonce) internal pure returns (uint56) {
        if (nonce >= 56) revert AlternatingNonceBitmap__flipNonce_nonceOutOfBounds();

        return (bitmap ^ (1 << nonce)).toUint56();
    }
}
