// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';

import { TightPack } from 'src/libraries/utils/TightPack.sol';

contract TestTightPack is Test {
    function testPackSlots() public {
        uint160 a = 1;
        uint160 b = 2;
        uint160 c = 3;

        (uint256 slot1, uint256 slot2) = TightPack.packSlots(a, b, c);
        console.log('slot1: ', slot1);
        console.log('slot2: ', slot2);

        (uint160 a2, uint160 b2, uint160 c2) = TightPack.unpackSlots(slot1, slot2);
        console.log('a2: ', a2);
        console.log('b2: ', b2);
        console.log('c2: ', c2);
    }
}
