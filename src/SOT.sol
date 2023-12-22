// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

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

import { SOTHash } from 'src/libraries/SOTHash.sol';
import { SOTParams } from 'src/libraries/SOTParams.sol';
import { SolverOrderType, SwapState } from 'src/structs/SOTStructs.sol';
import { SOTOracle } from 'src/SOTOracle.sol';

/**
    @title Solver Order Type.
    @notice Valantis Sovereign Liquidity Module.
 */
contract SOT is ISovereignALM, EIP712, SOTOracle {
    using Math for uint256;
    using SafeCast for uint256;
    using SignatureChecker for address;
    using SOTHash for SolverOrderType;

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error SOT__onlyPool();
    error SOT__constructor_invalidToken0();
    error SOT__constructor_invalidToken1();
    error SOT__getLiquidityQuote_invalidSignature();

    /************************************************
     *  IMMUTABLES
     ***********************************************/

    /**
	    @notice Sovereign Pool to which this Liquidity Module is bound.
    */
    address public immutable pool;

    /**
        @notice Address of pool's token0. 
     */
    address public immutable token0;

    /**
        @notice Address of pool's token1. 
     */
    address public immutable token1;

    /**
	    @notice Maximum delay, in seconds, for acceptance of SOT quotes.
    */
    uint32 public immutable maxDelay;

    /**
	    @notice Maximum price discount allowed for SOT quotes,
                expressed in basis-points.
    */
    uint16 public immutable solverMaxDiscountBips;

    /**
	    @notice Maximum allowed relative deviation
                between spot price and oracle price,
                expressed in basis-points.
     */
    uint16 public immutable oraclePriceMaxDiffBips;

    /**
	    @notice Bounds the growth rate, in basis-points, of the AMM fee 
					as time increases between last processed quote.
        @dev SOT reverts if feeGrowth exceeds these bounds.
     */
    uint16 public immutable minAmmFeeGrowth;
    uint16 public immutable maxAmmFeeGrowth;

    /**
	    @notice Minimum allowed AMM fee, in basis-points.
	    @dev SOT reverts if feeMin is below this value.
     */
    uint16 public immutable minAmmFee;

    /************************************************
     *  STORAGE
     ***********************************************/

    /**
		@notice Account that manages all access controls to this liquidity module.
     */
    address public manager;

    /**
	    @notice Address of account which is meant to validate SOT quote signatures.
        @dev Can be updated by `manager`.
     */
    address public signer;

    /**
	    @notice Maximum amount of token{0,1} to quote to solvers on each SOT.
        @dev Can be updated by `manager`.
	    @dev Since there can only be one SOT per block, this is also a maximum
             allowed SOT quote volume per block.
     */
    uint256 public maxToken0VolumeToQuote;
    uint256 public maxToken1VolumeToQuote;

    /**
	    @notice AMM square-root spot price, in Q96 format.
        @dev It can only be updated on AMM swaps or after processing a valid SOT quote.
     */
    uint160 public sqrtSpotPriceX96;

    /**
        @notice AMM position's square-root low and upper price bounds, in Q96 format.
        TODO: Use ticks to pack into one storage slot 
     */
    uint160 public sqrtPriceLowX96;
    uint160 public sqrtPriceHighX96;

    /**
        @notice Contains state variables which get updated on swaps. 
     */
    SwapState public swapState;

    /************************************************
     *  MODIFIERS
     ***********************************************/

    modifier onlyPool() {
        if (msg.sender != pool) {
            revert SOT__onlyPool();
        }
        _;
    }

    /************************************************
     *  CONSTRUCTOR
     ***********************************************/

    constructor(
        address _pool,
        address _token0,
        address _token1,
        uint32 _maxDelay,
        uint16 _solverMaxDiscountBips,
        uint16 _oraclePriceMaxDiffBips,
        uint32 _maxOracleUpdateDuration,
        uint16 _minAmmFeeGrowth,
        uint16 _maxAmmFeeGrowth,
        uint16 _minAmmFee,
        address _feedToken0,
        address _feedToken1
    )
        EIP712('Valantis Solver Order Type', '1')
        SOTOracle(_token0, _token1, _feedToken0, _feedToken1, _maxOracleUpdateDuration)
    {
        // TODO: Refactor into separate contracts/libraries + check params validity
        pool = _pool;

        if (_token0 != ISovereignPool(pool).token0()) {
            revert SOT__constructor_invalidToken0();
        }

        if (_token1 != ISovereignPool(pool).token1()) {
            revert SOT__constructor_invalidToken1();
        }

        token0 = _token0;
        token1 = _token1;

        maxDelay = _maxDelay;
        solverMaxDiscountBips = _solverMaxDiscountBips;

        oraclePriceMaxDiffBips = _oraclePriceMaxDiffBips;

        minAmmFeeGrowth = _minAmmFeeGrowth;
        maxAmmFeeGrowth = _maxAmmFeeGrowth;
        minAmmFee = _minAmmFee;
    }

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

    // TODO: Add getters and setters

    function getLiquidityQuote(
        ALMLiquidityQuoteInput memory _almLiquidityQuoteInput,
        bytes calldata _externalContext,
        bytes calldata /*_verifierData*/
    ) external override onlyPool returns (ALMLiquidityQuote memory) {
        (SolverOrderType memory sot, bytes memory signature) = abi.decode(_externalContext, (SolverOrderType, bytes));

        SwapState memory swapStateCache = swapState;

        SOTParams.validateBasicParams(
            sot.authorizedSender,
            sot.amountInMax,
            sot.amountOutMax,
            sot.signatureTimestamp,
            sot.expiry,
            _almLiquidityQuoteInput.amountInMinusFee,
            _almLiquidityQuoteInput.isZeroToOne ? maxToken1VolumeToQuote : maxToken0VolumeToQuote,
            swapStateCache.lastProcessedBlockTimestamp,
            swapStateCache.lastProcessedSignatureTimestamp
        );
        SOTParams.validateFeeParams(sot.feeMin, sot.feeGrowth, sot.feeMax, minAmmFee, minAmmFeeGrowth, maxAmmFeeGrowth);

        uint160 sqrtOraclePriceX96 = _getSqrtOraclePriceX96();

        SOTParams.validatePriceBounds(
            _almLiquidityQuoteInput.isZeroToOne
                ? Math.mulDiv(sot.amountOutMax, 1 << 192, sot.amountInMax).sqrt().toUint160()
                : Math.mulDiv(sot.amountInMax, 1 << 192, sot.amountOutMax).sqrt().toUint160(),
            sqrtSpotPriceX96,
            sot.sqrtSpotPriceX96New,
            sqrtOraclePriceX96,
            sqrtPriceLowX96,
            sqrtPriceHighX96,
            oraclePriceMaxDiffBips,
            solverMaxDiscountBips
        );

        bytes32 sotHash = sot.hashStruct();
        if (!signer.isValidSignatureNow(_hashTypedDataV4(sotHash), signature)) {
            revert SOT__getLiquidityQuote_invalidSignature();
        }

        ALMLiquidityQuote memory liquidityQuote;
        // Always true, since reserves must be stored in the pool
        liquidityQuote.quoteFromPoolReserves = true;
        liquidityQuote.amountOut = Math.mulDiv(
            _almLiquidityQuoteInput.amountInMinusFee,
            sot.amountOutMax,
            sot.amountInMax
        );
        liquidityQuote.amountInFilled = _almLiquidityQuoteInput.amountInMinusFee;

        // Update state
        swapState = SwapState({
            lastProcessedBlockTimestamp: uint32(block.timestamp),
            lastProcessedSignatureTimestamp: sot.signatureTimestamp,
            lastProcessedFeeGrowth: sot.feeGrowth,
            lastProcessedFeeMin: sot.feeMin,
            lastProcessedFeeMax: sot.feeMax
        });

        return liquidityQuote;
    }

    function onDepositLiquidityCallback(
        uint256 /*_amount0*/,
        uint256 /*_amount1*/,
        bytes memory /*_data*/
    ) external override onlyPool {}

    function onSwapCallback(
        bool /*_isZeroToOne*/,
        uint256 /*_amountIn*/,
        uint256 /*_amountOut*/
    ) external override onlyPool {}
}
