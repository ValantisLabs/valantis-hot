// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

/**
    @notice Helper library for tight packing multiplke uint160 values into minimum amount of uint256 slots.
 */
library TightPack {
    /**
        @notice Packs 3 uint160 values into 2 uint256 slots.
        @param a uint160 value to pack into slot1.
        @param b uint160 value to pack into slot1 and slot2.
        @param c uint160 value to pack into slot2.
        @return slot1 uint256 value containing a and b.
        @return slot2 uint256 value containing b and c.
        @dev slot1: << 32 empty bits | upper 64 bits of b | all 160 bits of a >>
             slot2: << lower 96 bits of b | all 160 bits of c >>
     */
    function packSlots(uint160 a, uint160 b, uint160 c) internal pure returns (uint256 slot1, uint256 slot2) {
        assembly {
            slot1 := or(shl(160, shr(96, b)), a)
            slot2 := or(shl(160, b), c)
        }
    }

    /**
        @notice Unpacks 2 uint256 slots into 3 uint160 values.
        @param slot1 uint256 value containing a and b.
        @param slot2 uint256 value containing b and c.
        @return a uint160 value unpacked from slot1.
        @return b uint160 value unpacked from slot1 and slot2.
        @return c uint160 value unpacked from slot2.
        @dev slot1: << 32 empty bits | upper 64 bits of b | all 160 bits of a >>
             slot2: << lower 96 bits of b | all 160 bits of c >>
     */
    function unpackSlots(uint256 slot1, uint256 slot2) internal pure returns (uint160 a, uint160 b, uint160 c) {
        assembly {
            a := shr(96, shl(96, slot1))
            c := shr(96, shl(96, slot2))
            b := or(shl(96, shr(160, slot1)), shr(160, slot2))
        }
    }
}
