// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';
import { console } from 'forge-std/console.sol';

import { TightPack } from 'src/libraries/utils/TightPack.sol';

contract TestTightPack is Test {
    TightPack.PackedState state;

    function testPackSlotsUint160(uint32 flags, uint160 a, uint160 b, uint160 c) public {
        TightPack.PackedState memory tempState = TightPack.packState(flags, a, b, c);
        state.slot1 = tempState.slot1;
        state.slot2 = tempState.slot2;

        (uint32 flags2, uint160 a2, uint160 b2, uint160 c2) = TightPack.unpackState(state);

        assertEq(flags, flags2, 'incorrect flags value');
        assertEq(a, a2, 'incorrect a value');
        assertEq(b, b2, 'incorrect b value');
        assertEq(c, c2, 'incorrect c value');
    }
}
