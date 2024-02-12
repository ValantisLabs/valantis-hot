// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

library SOTConstants {
    // TODO: Make the constants library internal
    /**
        @notice Maximum allowed solver fee, in basis-points.
      */
    uint16 public constant MAX_SOLVER_FEE_IN_BIPS = 100;

    /**
        @notice Min and max sqrt price bounds.
        @dev Same bounds as in https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickMath.sol.
     */
    uint160 public constant MIN_SQRT_PRICE = 4295128739;
    uint160 public constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;

    bytes32 public constant SOT_TYPEHASH =
        keccak256(
            // solhint-disable-next-line max-line-length
            'SolverOrderType(uint256 amountInMax,uint160 sqrtSolverPriceX96Discounted,uint160 sqrtSolverPriceX96Base,uint160 sqrtSpotPriceX96New,address authorizedSender,address authorizedRecipient,uint32 signatureTimestamp,uint32 expiry,uint16 feeMinToken0,uint16 feeMaxToken0,uint16 feeGrowthToken0,uint16 feeMinToken1,uint16 feeMaxToken1,uint16 feeGrowthToken1)'
        );

    /**
        @notice The constant value 2**96
     */
    uint256 public constant Q96 = 0x1000000000000000000000000;

    /**
        @notice The constant value 2**192
     */
    uint256 public constant Q192 = 0x1000000000000000000000000000000000000000000000000;

    /**
        @notice The constant value 10_000
     */
    uint256 public constant BIPS = 10_000;

    uint256 public constant MAX_SOT_QUOTES_IN_BLOCK = 32;

    uint8 internal constant PAUSE_FLAG = 0;

    uint8 internal constant REENTRANCY_FLAG = 1;
}
