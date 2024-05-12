// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';

import { TightPack } from '../../src/libraries/utils/TightPack.sol';
import { AMMState } from '../../src/structs/HOTStructs.sol';

contract TightPackHarness {
    AMMState public harnessState;

    function setState(uint160 a, uint160 b, uint160 c) external {
        TightPack.setState(harnessState, a, b, c);
    }

    function getState() external view returns (uint160, uint160, uint160) {
        return TightPack.getState(harnessState);
    }

    function setSqrtSpotPriceX96(uint160 a) external {
        TightPack.setSqrtSpotPriceX96(harnessState, a);
    }

    function getSqrtSpotPriceX96() external view returns (uint160) {
        return TightPack.getSqrtSpotPriceX96(harnessState);
    }
}

contract TestTightPack is Test {
    using TightPack for AMMState;

    TightPackHarness public harness;

    function setUp() public {
        harness = new TightPackHarness();
    }

    function test_PackSlotsUint160(uint160 a, uint160 b, uint160 c) public {
        harness.setState(a, b, c);

        (uint160 a2, uint160 b2, uint160 c2) = harness.getState();

        assertEq(a, a2, 'incorrect a value');
        assertEq(b, b2, 'incorrect b value');
        assertEq(c, c2, 'incorrect c value');
    }

    function test_SetSqrtSpotPriceX96(uint160 a, uint160 b, uint160 c, uint160 a2) public {
        harness.setState(a, b, c);

        assertEq(a, harness.getSqrtSpotPriceX96(), 'incorrect getSqrtSpotPriceX96');

        harness.setSqrtSpotPriceX96(a2);

        assertEq(a2, harness.getSqrtSpotPriceX96(), 'incorrect setSqrtSpotPriceX96');
    }
}
