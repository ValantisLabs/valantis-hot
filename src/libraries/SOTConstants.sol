// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

library SOTConstants {
    /**
        @notice Maximum allowed solver fee, in basis-points.
      */
    uint16 constant MAX_SOLVER_FEE_IN_BIPS = 100;

    /**
        @notice Min and max sqrt price bounds.
        @dev Same bounds as in https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickMath.sol.
     */
    uint160 public constant MIN_SQRT_PRICE = 4295128739;
    uint160 public constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;

    bytes32 public constant SOT_TYPEHASH =
        keccak256(
            // solhint-disable-next-line max-line-length
            'SolverOrderType(uint256 amountInMax,uint160 sqrtSolverPriceX96Discounted, uint160 sqrtSolverPriceX96Base,uint160 sqrtSpotPriceX96New,address authorizedSender,address authorizedRecipient,uint32 signatureTimestamp,uint32 expiry,uint16 feeMin,uint16 feeMax,uint16 feeGrowth)'
        );

    /**
        @notice The constant value 2**96
     */
    uint256 public constant Q96 = 0x1000000000000000000000000;

    /**
        @notice The constant value 10_000
     */
    uint256 public constant BIPS = 10_000;

    uint256 public constant MAX_DELAY = 10 minutes;

    uint256 public constant SOLVER_MAX_DISCOUNT = 5_000;

    uint256 public constant MAX_ORACLE_PRICE_DIFF = 5_000;
}
