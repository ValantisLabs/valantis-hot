// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';
import { console } from 'forge-std/console.sol';

import { TightPack } from 'src/libraries/utils/TightPack.sol';

contract TestTightPack is Test {
    function testPackSlotsUint160(uint160 a, uint160 b, uint160 c) public {
        (uint256 slot1, uint256 slot2) = TightPack.packSlots(a, b, c);

        (uint160 a2, uint160 b2, uint160 c2) = TightPack.unpackSlots(slot1, slot2);

        assertEq(a, a2, 'incorrect a value');
        assertEq(b, b2, 'incorrect b value');
        assertEq(c, c2, 'incorrect c value');
    }
}
