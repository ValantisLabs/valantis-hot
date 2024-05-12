// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import { AMMState } from '../../structs/HOTStructs.sol';

/**
    @notice Helper library for tight packing multiple uint160 values into minimum amount of uint256 slots.
 */
library TightPack {
    uint256 constant LOWER_160_MASK = 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff;
    uint256 constant UPPER_96_MASK = 0xffffffffffffffffffffffff0000000000000000000000000000000000000000;

    /************************************************
     *  FUNCTIONS
     ***********************************************/

    /**
        @notice Packs 3 uint160 values into 2 uint256 slots.
        @param a uint160 value to pack into slot1.
        @param b uint160 value to pack into slot1 and slot2.
        @param c uint160 value to pack into slot2.
        @dev slot1: << 32 free bits | upper 64 bits of b | all 160 bits of a >>
             slot2: << lower 96 bits of b | all 160 bits of c >>
     */
    function setState(AMMState storage state, uint160 a, uint160 b, uint160 c) internal {
        uint256 slot1;
        uint256 slot2;
        assembly {
            slot1 := or(shl(160, shr(96, b)), a)
            slot2 := or(shl(160, b), c)
        }

        state.slot1 = slot1;
        state.slot2 = slot2;
    }

    /**
        @notice Unpacks 2 uint256 slots into 3 uint160 values.
        @param state AMMState struct containing slot1 and slot2.
        @return a uint160 value unpacked from slot1.
        @return b uint160 value unpacked from slot1 and slot2.
        @return c uint160 value unpacked from slot2.
        @dev slot1: << 32 empty bits | upper 64 bits of b | all 160 bits of a >>
             slot2: << lower 96 bits of b | all 160 bits of c >>
     */
    function getState(AMMState storage state) internal view returns (uint160 a, uint160 b, uint160 c) {
        uint256 slot1 = state.slot1;
        uint256 slot2 = state.slot2;

        assembly {
            a := and(slot1, LOWER_160_MASK)
            c := and(slot2, LOWER_160_MASK)
            b := or(shl(96, shr(160, slot1)), shr(160, slot2))
        }
    }

    function getSqrtSpotPriceX96(AMMState storage state) internal view returns (uint160 a) {
        uint256 slot1 = state.slot1;
        assembly {
            a := and(slot1, LOWER_160_MASK)
        }
    }

    function setSqrtSpotPriceX96(AMMState storage state, uint160 a) internal {
        uint256 slot1 = state.slot1;
        assembly {
            slot1 := or(and(slot1, UPPER_96_MASK), a)
        }
        state.slot1 = slot1;
    }
}
