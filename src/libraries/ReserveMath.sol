// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import { LiquidityAmounts } from '../../lib/v3-periphery/contracts/libraries/LiquidityAmounts.sol';

import { ISovereignPool } from '../../lib/valantis-core/src/pools/interfaces/ISovereignPool.sol';

import { TightPack } from '../libraries/utils/TightPack.sol';
import { AMMState } from '../structs/HOTStructs.sol';

library ReserveMath {
    using TightPack for AMMState;

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
