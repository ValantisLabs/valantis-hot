// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SOTParams } from 'src/libraries/SOTParams.sol';
import { SolverOrderType, AMMState } from 'src/structs/SOTStructs.sol';
import { TightPack } from 'src/libraries/utils/TightPack.sol';

contract SOTParamsHelper {
    using TightPack for AMMState;

    AMMState public ammStateStorage;

    function setState(uint32 flags, uint160 a, uint160 b, uint160 c) public {
        ammStateStorage.setState(flags, a, b, c);
    }

    function validateBasicParams(
        SolverOrderType memory sot,
        uint256 amountOut,
        address sender,
        address recipient,
        uint256 amountIn,
        uint256 tokenOutMaxBound,
        uint32 maxDelay,
        uint56 alternatingNonceBitmap
    ) public view {
        SOTParams.validateBasicParams(
            sot,
            amountOut,
            sender,
            recipient,
            amountIn,
            tokenOutMaxBound,
            maxDelay,
            alternatingNonceBitmap
        );
    }

    function validateFeeParams(
        SolverOrderType memory sot,
        uint16 feeMinBound,
        uint16 feeGrowthMinBound,
        uint16 feeGrowthMaxBound
    ) public pure {
        SOTParams.validateFeeParams(sot, feeMinBound, feeGrowthMinBound, feeGrowthMaxBound);
    }

    function validatePriceConsistency(
        uint160 sqrtSolverPriceX96,
        uint160 sqrtSpotPriceNewX96,
        uint160 sqrtOraclePriceX96,
        uint256 oraclePriceMaxDiffBips,
        uint256 solverMaxDiscountBips
    ) public view {
        SOTParams.validatePriceConsistency(
            ammStateStorage,
            sqrtSolverPriceX96,
            sqrtSpotPriceNewX96,
            sqrtOraclePriceX96,
            oraclePriceMaxDiffBips,
            solverMaxDiscountBips
        );
    }

    function validatePriceBounds(
        uint160 sqrtSpotPriceX96,
        uint160 sqrtPriceLowX96,
        uint160 sqrtPriceHighX96
    ) public pure {
        SOTParams.validatePriceBounds(sqrtSpotPriceX96, sqrtPriceLowX96, sqrtPriceHighX96);
    }

    function hashParams(SolverOrderType memory sotParams) public pure returns (bytes32) {
        return SOTParams.hashParams(sotParams);
    }
}
