// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {
    IERC20Metadata
} from 'valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { EIP712 } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol';
import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
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
import { AggregatorV3Interface } from 'src/vendor/chainlink/AggregatorV3Interface.sol';

/**
    @title Solver Order Type.
    @notice Valantis Sovereign Liquidity Module.
 */
contract SOT is ISovereignALM, EIP712 {
    using SignatureChecker for address;
    using SOTHash for SolverOrderType;

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error SOT__invalidSignature();

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
	    @notice Maximum allowed duration for each oracle update, in seconds.
        @dev Oracle prices are considered stale beyond this threshold,
             meaning that all swaps should revert.
     */
    uint32 public immutable maxOracleUpdateDuration;

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

    /**
	    @notice Decimals for token{0,1}.
        @dev `token0` and `token1` must be the same as this module's Sovereign Pool.
     */
    uint8 public immutable token0Decimals;
    uint8 public immutable token1Decimals;

    /**
	    @notice Base unit for token{0,1}.
          For example: token0Base = 10 ** token0Decimals;
        @dev `token0` and `token1` must be the same as this module's Sovereign Pool.
     */
    uint256 public immutable token0Base;
    uint256 public immutable token1Base;

    /**
	    @notice Price feeds for token{0,1}, denominated in USD.
	    @dev These must be valid Chainlink Price Feeds.
     */
    AggregatorV3Interface public immutable feedToken0;
    AggregatorV3Interface public immutable feedToken1;

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
	    @notice AMM spot price.
          TODO: Depending on the final AMM design, this format might change.
        @dev It can only be updated on AMM swaps or after processing a valid SOT quote.
     */
    uint256 public spotPriceX128;

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
        uint32 _maxDelay,
        uint16 _solverMaxDiscountBips,
        uint16 _oraclePriceMaxDiffBips,
        uint32 _maxOracleUpdateDuration,
        uint16 _minAmmFeeGrowth,
        uint16 _maxAmmFeeGrowth,
        uint16 _minAmmFee,
        address _feedToken0,
        address _feedToken1
    ) EIP712('Valantis Solver Order Type', '1') {
        // TODO: Refactor into separate contracts/libraries + check params validity
        pool = _pool;

        token0 = ISovereignPool(pool).token0();
        token1 = ISovereignPool(pool).token1();

        maxDelay = _maxDelay;
        solverMaxDiscountBips = _solverMaxDiscountBips;

        oraclePriceMaxDiffBips = _oraclePriceMaxDiffBips;
        maxOracleUpdateDuration = _maxOracleUpdateDuration;

        minAmmFeeGrowth = _minAmmFeeGrowth;
        maxAmmFeeGrowth = _maxAmmFeeGrowth;
        minAmmFee = _minAmmFee;

        token0Decimals = IERC20Metadata(token0).decimals();
        token1Decimals = IERC20Metadata(token1).decimals();

        token0Base = 10 ** token0Decimals;
        token1Base = 10 ** token1Decimals;

        feedToken0 = AggregatorV3Interface(_feedToken0);
        feedToken1 = AggregatorV3Interface(_feedToken1);
    }

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

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
            sot.signatureTimestamp,
            sot.expiry,
            _almLiquidityQuoteInput.amountInMinusFee,
            swapStateCache.lastProcessedBlockTimestamp,
            swapStateCache.lastProcessedSignatureTimestamp
        );

        // TODO: validate remaining params

        bytes32 sotHash = sot.hashStruct();
        if (!signer.isValidSignatureNow(_hashTypedDataV4(sotHash), signature)) {
            revert SOT__invalidSignature();
        }

        uint256 amountOut = _almLiquidityQuoteInput.isZeroToOne
            ? Math.mulDiv(_almLiquidityQuoteInput.amountInMinusFee, sot.amountOutMax, sot.amountInMax)
            : Math.mulDiv(_almLiquidityQuoteInput.amountInMinusFee, sot.amountInMax, sot.amountOutMax);

        ALMLiquidityQuote memory liquidityQuote;
        // Always true, since reserves must be stored in the pool
        liquidityQuote.quoteFromPoolReserves = true;
        liquidityQuote.amountOut = amountOut;
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
