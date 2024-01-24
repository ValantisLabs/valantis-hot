// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SOTParams } from 'src/libraries/SOTParams.sol';

import { SolverOrderType } from 'src/structs/SOTStructs.sol';
import { TightPack } from 'src/libraries/utils/TightPack.sol';

contract SOTParamsHelper {
    TightPack.PackedState ammStateStorage;

    function validateBasicParams(
        SolverOrderType memory sot,
        uint256 amountOut,
        address sender,
        address recipient,
        uint256 amountIn,
        uint256 tokenOutMaxBound,
        uint32 maxDelay,
        uint64 alternatingNonceBitmap
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
        TightPack.PackedState memory ammState,
        uint160 sqrtSolverPriceX96,
        uint160 sqrtSpotPriceNewX96,
        uint160 sqrtOraclePriceX96,
        uint256 oraclePriceMaxDiffBips,
        uint256 solverMaxDiscountBips
    ) public {
        ammStateStorage = ammState;
        SOTParams.validatePriceConsistency(
            ammStateStorage,
            sqrtSolverPriceX96,
            sqrtSpotPriceNewX96,
            sqrtOraclePriceX96,
            oraclePriceMaxDiffBips,
            solverMaxDiscountBips
        );
    }
}
