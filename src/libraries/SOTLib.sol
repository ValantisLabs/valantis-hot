// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SwapMath } from '@uniswap/v3-core/contracts/libraries/SwapMath.sol';
import { LiquidityAmounts } from '@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol';

import { IERC20 } from 'valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from 'valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import { EIP712 } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol';
import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {
    SignatureChecker
} from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';
import {
    ISovereignALM,
    ALMLiquidityQuote,
    ALMLiquidityQuoteInput
} from 'valantis-core/src/alm/interfaces/ISovereignALM.sol';
import { ISovereignPool } from 'valantis-core/src/pools/interfaces/ISovereignPool.sol';
import {
    ISwapFeeModuleMinimal,
    SwapFeeModuleData
} from 'valantis-core/src/swap-fee-modules/interfaces/ISwapFeeModule.sol';

import { SOTLib } from 'src/libraries/SOTLib.sol';
import { SOTParams } from 'src/libraries/SOTParams.sol';
import { TightPack } from 'src/libraries/utils/TightPack.sol';
import { AlternatingNonceBitmap } from 'src/libraries/AlternatingNonceBitmap.sol';
import { SOTConstants } from 'src/libraries/SOTConstants.sol';
import {
    SolverOrderType,
    SolverWriteSlot,
    SolverReadSlot,
    SOTConstructorArgs,
    AMMState
} from 'src/structs/SOTStructs.sol';
import { SOTOracle } from 'src/SOTOracle.sol';
import { ISOT } from 'src/interfaces/ISOT.sol';

library SOTLib {
    using TightPack for AMMState;

    // function setPriceBounds(
    //     AMMState storage _ammState,
    //     SolverReadSlot memory solverReadSlot,
    //     uint160 _sqrtPriceLowX96,
    //     uint160 _sqrtPriceHighX96,
    //     uint160 _expectedSqrtSpotPriceLowerX96,
    //     uint160 _expectedSqrtSpotPriceUpperX96
    // ) external {
    //     // Allow `liquidityProvider` to cross-check sqrt spot price against expected bounds,
    //     // to protect against its manipulation
    //     uint160 sqrtSpotPriceX96Cache = checkSpotPriceRange(
    //         _ammState,
    //         _expectedSqrtSpotPriceLowerX96,
    //         _expectedSqrtSpotPriceUpperX96
    //     );

    //     // It is sufficient to check only feedToken0, because either both of the feeds are set, or both are null.
    //     if (address(feedToken0) != address(0)) {
    //         // Feeds have been set, oracle deviation should be checked.
    //         // If feeds are not set, then SOT is in AMM-only mode, and oracle deviation check is not required.
    //         if (
    //             !SOTParams.checkPriceDeviation(
    //                 sqrtSpotPriceX96Cache,
    //                 getSqrtOraclePriceX96(),
    //                 solverReadSlotCache.maxOracleDeviationBipsLower,
    //                 solverReadSlotCache.maxOracleDeviationBipsUpper
    //             )
    //         ) {
    //             revert SOT__setPriceBounds_spotPriceAndOracleDeviation();
    //         }
    //     }

    //     // Check that new bounds are valid,
    //     // and do not exclude current spot price
    //     SOTParams.validatePriceBounds(sqrtSpotPriceX96Cache, _sqrtPriceLowX96, _sqrtPriceHighX96);

    //     // Update AMM sqrt spot price, sqrt price low and sqrt price high
    //     _ammState.setState(sqrtSpotPriceX96Cache, _sqrtPriceLowX96, _sqrtPriceHighX96);

    //     // Update AMM liquidity
    //     _updateAMMLiquidity(_calculateAMMLiquidity());

    //     emit PriceBoundSet(_sqrtPriceLowX96, _sqrtPriceHighX96);
    // }

    /**
        @notice Returns the AMM reserves assuming some AMM spot price.
        @param sqrtSpotPriceX96New square-root price to query AMM reserves for, in Q96 format.
        @return reserve0 Reserves of token0 at `sqrtSpotPriceX96New`.
        @return reserve1 Reserves of token1 at `sqrtSpotPriceX96New`.
     */
    function getReservesAtPrice(
        AMMState storage _ammState,
        address _pool,
        uint128 _effectiveAMMLiquidity,
        uint160 sqrtSpotPriceX96New
    ) external view returns (uint256 reserve0, uint256 reserve1) {
        (uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96) = _ammState.getState();

        (reserve0, reserve1) = ISovereignPool(_pool).getReserves();

        uint128 effectiveAMMLiquidityCache = _effectiveAMMLiquidity;

        (uint256 activeReserve0, uint256 activeReserve1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtSpotPriceX96,
            sqrtPriceLowX96,
            sqrtPriceHighX96,
            effectiveAMMLiquidityCache
        );

        uint256 passiveReserve0 = reserve0 - activeReserve0;
        uint256 passiveReserve1 = reserve1 - activeReserve1;

        (activeReserve0, activeReserve1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtSpotPriceX96New,
            sqrtPriceLowX96,
            sqrtPriceHighX96,
            effectiveAMMLiquidityCache
        );

        reserve0 = passiveReserve0 + activeReserve0;
        reserve1 = passiveReserve1 + activeReserve1;
    }
}
