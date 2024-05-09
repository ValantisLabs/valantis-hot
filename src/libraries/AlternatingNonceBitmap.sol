// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import { SafeCast } from '../../lib/valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

/**
    @notice Helper library for creating an alternate nonce mechanism.
        * Each nonce is represented by a single bit in a 56-bit bitmap.
        * The user can check if the nonce is consumed or not using the expectedFlag parameter.
        If current nonce state == expectedFlag, then the nonce is not consumed, otherwise this is a replay.
    
    @dev The entity signing the nonce has to keep a track of the state of the bitmap, 
        if the expected flag is set incorrectly, then replay is possible.
        
    @dev It is the responsibility of the caller to ensure they use checkNonce and flipNonce correctly.
 */
library AlternatingNonceBitmap {
    using SafeCast for uint256;

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error AlternatingNonceBitmap__checkNonce_nonceOutOfBounds();
    error AlternatingNonceBitmap__checkNonce_expectedFlagInvalid();
    error AlternatingNonceBitmap__flipNonce_nonceOutOfBounds();

    /************************************************
     *  FUNCTIONS
     ***********************************************/

    /**
        @notice Checks if the nonce is consumed or not.
        @param bitmap 56-bit bitmap representing the state of the nonces.
        @param nonce Nonce to check.
        @param expectedFlag Expected flag for the nonce.
        @return True if the nonce is in expected state, otherwise false.
     */
    function checkNonce(uint56 bitmap, uint8 nonce, uint8 expectedFlag) internal pure returns (bool) {
        if (nonce >= 56) revert AlternatingNonceBitmap__checkNonce_nonceOutOfBounds();
        if (expectedFlag > 1) revert AlternatingNonceBitmap__checkNonce_expectedFlagInvalid();

        return ((bitmap & (1 << nonce)) >> nonce) == expectedFlag;
    }

    /**
        @notice Flips the state of the nonce.
        @param bitmap 56-bit bitmap representing the state of the nonces.
        @param nonce Nonce to flip.
        @return New bitmap with the nonce state flipped.
     */
    function flipNonce(uint56 bitmap, uint8 nonce) internal pure returns (uint56) {
        if (nonce >= 56) revert AlternatingNonceBitmap__flipNonce_nonceOutOfBounds();

        return (bitmap ^ (1 << nonce)).toUint56();
    }
}
