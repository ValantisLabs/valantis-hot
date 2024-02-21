// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';

import { TightPack } from 'src/libraries/utils/TightPack.sol';
import { AMMState } from 'src/structs/SOTStructs.sol';

contract TightPackHarness {
    AMMState public harnessState;

    function setState(uint32 flags, uint160 a, uint160 b, uint160 c) external {
        TightPack.setState(harnessState, flags, a, b, c);
    }

    function getState() external view returns (uint32, uint160, uint160, uint160) {
        return TightPack.getState(harnessState);
    }

    function setFlag(uint8 index, bool value) external {
        TightPack.setFlag(harnessState, index, value);
    }

    function getFlag(uint8 index) external view returns (bool) {
        return TightPack.getFlag(harnessState, index);
    }

    function setA(uint160 a) external {
        TightPack.setA(harnessState, a);
    }

    function getA() external view returns (uint160) {
        return TightPack.getA(harnessState);
    }
}

contract TestTightPack is Test {
    using TightPack for AMMState;

    TightPackHarness public harness;

    function setUp() public {
        harness = new TightPackHarness();
    }

    function test_PackSlotsUint160(uint32 flags, uint160 a, uint160 b, uint160 c) public {
        harness.setState(flags, a, b, c);

        (uint32 flags2, uint160 a2, uint160 b2, uint160 c2) = harness.getState();

        assertEq(flags, flags2, 'incorrect flags value');
        assertEq(a, a2, 'incorrect a value');
        assertEq(b, b2, 'incorrect b value');
        assertEq(c, c2, 'incorrect c value');
    }

    function test_flags(uint32 flags, uint160 a, uint160 b, uint160 c, uint8 index) public {
        index = uint8(bound(index, 0, 31));

        harness.setState(flags, a, b, c);

        harness.setFlag(index, true);
        assertTrue(harness.getFlag(index), 'flag not set');

        harness.setFlag(index, false);

        assertFalse(harness.getFlag(index), 'flag not unset');

        (, uint160 a2, uint160 b2, uint160 c2) = harness.getState();

        assertEq(a, a2, 'incorrect a value');
        assertEq(b, b2, 'incorrect b value');
        assertEq(c, c2, 'incorrect c value');
    }

    function test_flags_indexOutOfBounds() public {
        vm.expectRevert(TightPack.TightPack__invalidIndex.selector);
        harness.setFlag(32, true);

        vm.expectRevert(TightPack.TightPack__invalidIndex.selector);
        harness.getFlag(32);
    }

    function test_setA(uint32 flags, uint160 a, uint160 b, uint160 c, uint160 a2) public {
        harness.setState(flags, a, b, c);

        assertEq(a, harness.getA(), 'incorrect getA');

        harness.setA(a2);

        assertEq(a2, harness.getA(), 'incorrect setA');
    }
}
