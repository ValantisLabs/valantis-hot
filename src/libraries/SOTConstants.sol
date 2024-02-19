// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

/**
    @notice Stores all constants used in the family of SOT Contracts.
 */
library SOTConstants {
    /**
        @notice Maximum allowed solver fee, in basis-points.
      */
    uint16 internal constant MAX_SOLVER_FEE_IN_BIPS = 100;

    /**
        @notice Min and max sqrt price bounds.
        @dev Same bounds as in https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickMath.sol.
     */
    uint160 internal constant MIN_SQRT_PRICE = 4295128739;
    uint160 internal constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;

    /**
        @notice The typehash for the SolverOrderType struct for EIP-712 signatures.
     */
    bytes32 internal constant SOT_TYPEHASH =
        keccak256(
            // solhint-disable-next-line max-line-length
            'SolverOrderType(uint256 amountInMax,uint160 sqrtSolverPriceX96Discounted,uint160 sqrtSolverPriceX96Base,uint160 sqrtSpotPriceX96New,address authorizedSender,address authorizedRecipient,uint32 signatureTimestamp,uint32 expiry,uint16 feeMinToken0,uint16 feeMaxToken0,uint16 feeGrowthInPipsToken0,uint16 feeMinToken1,uint16 feeMaxToken1,uint16 feeGrowthInPipsToken1,uint8 nonce,uint8 expectedFlag)'
        );

    /**
        @notice The constant value 2**96
     */
    uint256 internal constant Q96 = 0x1000000000000000000000000;

    /**
        @notice The constant value 2**192
     */
    uint256 internal constant Q192 = 0x1000000000000000000000000000000000000000000000000;

    /**
        @notice The constant value 10_000
     */
    uint256 internal constant BIPS = 10_000;

    /**
        @notice The maximum number of SOT quotes that can be processed in a single block.
     */
    uint256 internal constant MAX_SOT_QUOTES_IN_BLOCK = 56;

    /**
        @notice The index of the pause flag in the flags bitmap.
            Responsible for pausing and unpausing all functions except withdrawal in the SOT.
     */
    uint8 internal constant PAUSE_FLAG = 0;
}
