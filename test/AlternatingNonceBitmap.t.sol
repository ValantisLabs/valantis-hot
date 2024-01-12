// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';
import { console } from 'forge-std/console.sol';

import { AlternatingNonceBitmap } from 'src/libraries/AlternatingNonceBitmap.sol';

contract TestAlternatingNonceBitmap is Test {
    function test__checkNonce_general() public {
        uint64 bitmap = 8; // 1000

        assertTrue(AlternatingNonceBitmap.checkNonce(bitmap, 3, 1), 'incorrect nonce check 1');
        assertFalse(AlternatingNonceBitmap.checkNonce(bitmap, 2, 1), 'incorrect nonce check 2');
    }

    function test__checkNonce_edgeCaseMax() public {
        uint64 bitmap = 0x8000000000000000; // 1 at 63rd bit ( 2 * 63)

        assertTrue(AlternatingNonceBitmap.checkNonce(bitmap, 63, 1), 'incorrect nonce check 3');
        assertFalse(AlternatingNonceBitmap.checkNonce(bitmap, 63, 0), 'incorrect nonce check 4');
    }

    function test__checkNonce_edgeCaseMin() public {
        uint64 bitmap = 1; // 1 at 63rd bit ( 2 * 63)

        assertTrue(AlternatingNonceBitmap.checkNonce(bitmap, 0, 1), 'incorrect nonce check 5');
        assertFalse(AlternatingNonceBitmap.checkNonce(bitmap, 0, 0), 'incorrect nonce check 6');
    }

    function test__checkNonce_generalMixed() public {
        uint64 bitmap = 13; // 1101

        assertTrue(AlternatingNonceBitmap.checkNonce(bitmap, 0, 1), 'incorrect nonce check 7');
        assertTrue(AlternatingNonceBitmap.checkNonce(bitmap, 1, 0), 'incorrect nonce check 8');
        assertTrue(AlternatingNonceBitmap.checkNonce(bitmap, 2, 1), 'incorrect nonce check 9');
        assertTrue(AlternatingNonceBitmap.checkNonce(bitmap, 3, 1), 'incorrect nonce check 10');
    }

    function test__checkNonce_exceedingNonceValue() public {
        uint64 bitmap = 8; // 1000

        vm.expectRevert('ANB: nonce out of bounds');
        AlternatingNonceBitmap.checkNonce(bitmap, 64, 1);
    }

    function test__checkNonce_incorrectExpectedValue() public {
        uint64 bitmap = 8; // 1000

        vm.expectRevert('ANB: expectedFlag must be 0 or 1');
        AlternatingNonceBitmap.checkNonce(bitmap, 4, 2);
    }

    function test__flipNonce_general() public {
        uint64 bitmap = 8; // 1000

        assertEq(AlternatingNonceBitmap.flipNonce(bitmap, 3), 0, 'incorrect nonce flip 1');
        assertEq(AlternatingNonceBitmap.flipNonce(bitmap, 2), 12, 'incorrect nonce flip 2');
    }

    function test__flipNonce_exceedingNonceValue() public {
        uint64 bitmap = 8; // 1000

        vm.expectRevert('ANB: nonce out of bounds');
        AlternatingNonceBitmap.flipNonce(bitmap, 64);
    }

    function test__flipNonce_fuzz(uint64 bitmap, uint8 nonce) public {
        if (nonce >= 64) {
            vm.expectRevert('ANB: nonce out of bounds');
        }
        // If the same nonce is flipped twice, we should get back the same bitmap.
        assertEq(
            bitmap,
            AlternatingNonceBitmap.flipNonce(AlternatingNonceBitmap.flipNonce(bitmap, nonce), nonce),
            'incorrect nonce flip 3'
        );
    }
}
