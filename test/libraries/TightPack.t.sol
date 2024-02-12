// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';

import { TightPack } from 'src/libraries/utils/TightPack.sol';
import { AMMState } from 'src/structs/SOTStructs.sol';

contract TestTightPack is Test {
    using TightPack for AMMState;

    AMMState state;

    function testPackSlotsUint160(uint32 flags, uint160 a, uint160 b, uint160 c) public {
        state.setState(flags, a, b, c);

        (uint32 flags2, uint160 a2, uint160 b2, uint160 c2) = state.getState();

        assertEq(flags, flags2, 'incorrect flags value');
        assertEq(a, a2, 'incorrect a value');
        assertEq(b, b2, 'incorrect b value');
        assertEq(c, c2, 'incorrect c value');
    }

    function testFlags(uint32 flags, uint160 a, uint160 b, uint160 c, uint8 rand) public {
        state.setState(flags, a, b, c);

        if (rand > 31) {
            vm.expectRevert(TightPack.TightPack__invalidIndex.selector);
        }

        state.setFlag(rand, true);
        assertTrue(state.getFlag(rand), 'flag not set');

        state.setFlag(rand, false);

        assertFalse(state.getFlag(rand), 'flag not unset');

        (, uint160 a2, uint160 b2, uint160 c2) = state.getState();

        assertEq(a, a2, 'incorrect a value');
        assertEq(b, b2, 'incorrect b value');
        assertEq(c, c2, 'incorrect c value');
    }

    function testSetA(uint32 flags, uint160 a, uint160 b, uint160 c, uint160 a2) public {
        state.setState(flags, a, b, c);

        assertEq(a, state.getA(), 'incorrect getA');

        state.setA(a2);

        assertEq(a2, state.getA(), 'incorrect setA');
    }
}
