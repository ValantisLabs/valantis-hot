// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';
import { console } from 'forge-std/console.sol';

import { AlternatingNonceBitmap } from '../../src/libraries/AlternatingNonceBitmap.sol';

contract AlternatingNonceBitmapHarness {
    function flipNonce(uint56 bitmap, uint8 nonce) external pure returns (uint56) {
        uint56 result = AlternatingNonceBitmap.flipNonce(bitmap, nonce);
        return result;
    }

    function checkNonce(uint56 bitmap, uint8 nonce, uint8 expectedFlag) external pure returns (bool) {
        bool result = AlternatingNonceBitmap.checkNonce(bitmap, nonce, expectedFlag);
        return result;
    }
}

contract TestAlternatingNonceBitmap is Test {
    AlternatingNonceBitmapHarness harness;

    function setUp() public {
        harness = new AlternatingNonceBitmapHarness();
    }

    function test__checkNonce_general() public {
        uint56 bitmap = 8; // 1000

        assertTrue(harness.checkNonce(bitmap, 3, 1), 'incorrect nonce check 1');
        assertFalse(harness.checkNonce(bitmap, 2, 1), 'incorrect nonce check 2');
    }

    function test__checkNonce_edgeCaseMax() public {
        uint56 bitmap = 0xffffffffffffff; // 1 at 55th bit

        assertTrue(harness.checkNonce(bitmap, 55, 1), 'incorrect nonce check 3');
        assertFalse(harness.checkNonce(bitmap, 55, 0), 'incorrect nonce check 4');
    }

    function test__checkNonce_edgeCaseMin() public {
        uint56 bitmap = 1;

        assertTrue(harness.checkNonce(bitmap, 0, 1), 'incorrect nonce check 5');
        assertFalse(harness.checkNonce(bitmap, 0, 0), 'incorrect nonce check 6');
    }

    function test__checkNonce_generalMixed() public {
        uint56 bitmap = 13; // 1101

        assertTrue(harness.checkNonce(bitmap, 0, 1), 'incorrect nonce check 7');
        assertTrue(harness.checkNonce(bitmap, 1, 0), 'incorrect nonce check 8');
        assertTrue(harness.checkNonce(bitmap, 2, 1), 'incorrect nonce check 9');
        assertTrue(harness.checkNonce(bitmap, 3, 1), 'incorrect nonce check 10');
    }

    function test__checkNonce_exceedingNonceValue() public {
        uint56 bitmap = 8; // 1000

        vm.expectRevert(AlternatingNonceBitmap.AlternatingNonceBitmap__checkNonce_nonceOutOfBounds.selector);
        harness.checkNonce(bitmap, 56, 1);
    }

    function test__checkNonce_incorrectExpectedValue() public {
        uint56 bitmap = 8; // 1000

        vm.expectRevert(AlternatingNonceBitmap.AlternatingNonceBitmap__checkNonce_expectedFlagInvalid.selector);

        harness.checkNonce(bitmap, 4, 2);
    }

    function test__flipNonce_general() public {
        uint56 bitmap = 8; // 1000

        assertEq(harness.flipNonce(bitmap, 3), 0, 'incorrect nonce flip 1');
        assertEq(harness.flipNonce(bitmap, 2), 12, 'incorrect nonce flip 2');
    }

    function test__flipNonce_exceedingNonceValue() public {
        uint56 bitmap = 8; // 1000

        vm.expectRevert(AlternatingNonceBitmap.AlternatingNonceBitmap__flipNonce_nonceOutOfBounds.selector);
        harness.flipNonce(bitmap, 56);
    }

    function test__flipNonce_fuzz(uint56 bitmap, uint8 nonce) public {
        uint56 expectedBitmap;
        if (nonce >= 56) {
            vm.expectRevert(AlternatingNonceBitmap.AlternatingNonceBitmap__flipNonce_nonceOutOfBounds.selector);
            expectedBitmap = harness.flipNonce(bitmap, nonce);
        } else {
            // If the same nonce is flipped twice, we should get back the same bitmap.
            expectedBitmap = harness.flipNonce(bitmap, nonce);
            assertEq(bitmap, harness.flipNonce(expectedBitmap, nonce), 'incorrect nonce flip 3');
        }
    }
}
