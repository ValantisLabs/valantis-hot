// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { LiquidityAmounts } from '@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol';
import { SwapMath } from '@uniswap/v3-core/contracts/libraries/SwapMath.sol';

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
    using SafeERC20 for IERC20;

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error SOT__onlyPool();
    error SOT__onlyManager();
    error SOT__onlyLiquidityProvider();
    error SOT__constructor_invalidMinAmmFee();
    error SOT__constructor_invalidMaxAmmFeeGrowth();
    error SOT__constructor_invalidMinAmmFeeGrowth();
    error SOT__constructor_invalidMaxDelay();
    error SOT__constructor_invalidOracleMaxDiff();
    error SOT__constructor_invalidSolverDiscount();
    error SOT__constructor_invalidSovereignPool();
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
	    @notice Address of account which is meant to deposit & withdraw liquidity.
        @dev Can be updated by `manager`.
     */
    address public liquidityProvider;

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

    modifier onlyManager() {
        if (msg.sender != manager) {
            revert SOT__onlyManager();
        }
        _;
    }

    modifier onlyLiquidityProvider() {
        if (msg.sender != liquidityProvider) {
            revert SOT__onlyLiquidityProvider();
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
        if (_pool == address(0)) {
            revert SOT__constructor_invalidSovereignPool();
        }

        pool = _pool;

        if (_token0 != ISovereignPool(pool).token0()) {
            revert SOT__constructor_invalidToken0();
        }

        if (_token1 != ISovereignPool(pool).token1()) {
            revert SOT__constructor_invalidToken1();
        }

        token0 = _token0;
        token1 = _token1;

        if (_maxDelay > 10 minutes) {
            revert SOT__constructor_invalidMaxDelay();
        }

        maxDelay = _maxDelay;

        if (_solverMaxDiscountBips > 5_000) {
            revert SOT__constructor_invalidSolverDiscount();
        }

        solverMaxDiscountBips = _solverMaxDiscountBips;

        if (_oraclePriceMaxDiffBips > 5_000) {
            revert SOT__constructor_invalidOracleMaxDiff();
        }

        oraclePriceMaxDiffBips = _oraclePriceMaxDiffBips;

        if (_minAmmFeeGrowth > 10_000) {
            revert SOT__constructor_invalidMinAmmFeeGrowth();
        }

        minAmmFeeGrowth = _minAmmFeeGrowth;

        if (_maxAmmFeeGrowth > 10_000) {
            revert SOT__constructor_invalidMaxAmmFeeGrowth();
        }

        maxAmmFeeGrowth = _maxAmmFeeGrowth;

        if (_minAmmFee > 10_000) {
            revert SOT__constructor_invalidMinAmmFee();
        }

        minAmmFee = _minAmmFee;
    }

    /************************************************
     *  SETTER FUNCTIONS
     ***********************************************/

    /**
        @notice Changes the manager of the pool ( To be protected by timelock )
     */
    function setManager(address _manager) external onlyManager {
        manager = _manager;
    }

    /**
        @notice Changes the signer of the pool ( To be protected by timelock )
     */
    function setSigner(address _signer) external onlyManager {
        signer = _signer;
    }

    /**
        @notice Changes the maximum token volumes available for a single SOT quote ( To be protected by timelock )
     */
    function setMaxTokenVolumes(uint256 _maxToken0VolumeToQuote, uint256 _maxToken1VolumeToQuote) external onlyManager {
        maxToken0VolumeToQuote = _maxToken0VolumeToQuote;
        maxToken1VolumeToQuote = _maxToken1VolumeToQuote;
    }

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

    function getLiquidityQuote(
        ALMLiquidityQuoteInput memory _almLiquidityQuoteInput,
        bytes calldata _externalContext,
        bytes calldata /*_verifierData*/
    ) external override onlyPool returns (ALMLiquidityQuote memory liquidityQuote) {
        if (_externalContext.length == 0) {
            // AMM Swap
            sqrtSpotPriceX96 = _ammSwap(_almLiquidityQuoteInput, liquidityQuote);
        } else {
            // Solver Swap
            sqrtSpotPriceX96 = _solverSwap(_almLiquidityQuoteInput, _externalContext, liquidityQuote);
        }
    }

    function depositLiquidity(uint256 _amount0, uint256 _amount1) external onlyLiquidityProvider {
        ISovereignPool(pool).depositLiquidity(_amount0, _amount1, liquidityProvider, '', '');
    }

    function withdrawLiquidity(uint256 _amount0, uint256 _amount1) external onlyLiquidityProvider {
        ISovereignPool(pool).withdrawLiquidity(_amount0, _amount1, liquidityProvider, liquidityProvider, '');
    }

    function onDepositLiquidityCallback(
        uint256 _amount0,
        uint256 _amount1,
        bytes memory /*_data*/
    ) external override onlyPool {
        if (_amount0 > 0) {
            IERC20(token0).safeTransferFrom(liquidityProvider, msg.sender, _amount0);
        }

        if (_amount1 > 0) {
            IERC20(token1).safeTransferFrom(liquidityProvider, msg.sender, _amount1);
        }
    }

    function onSwapCallback(
        bool /*_isZeroToOne*/,
        uint256 /*_amountIn*/,
        uint256 /*_amountOut*/
    ) external override onlyPool {}

    /************************************************
     *  INTERNAL FUNCTIONS
     ***********************************************/

    function _getAMMSwapFee() private view returns (uint16) {
        SwapState memory swapStateCache = swapState;

        uint32 fee = uint32(swapStateCache.lastProcessedFeeGrowth) *
            uint32(block.timestamp - swapStateCache.lastProcessedSignatureTimestamp);
        // Add minimum fee
        fee += uint32(swapStateCache.lastProcessedFeeMin);
        // Cap fee if necessary
        if (fee > uint32(swapStateCache.lastProcessedFeeMax)) {
            fee = uint32(swapStateCache.lastProcessedFeeMax);
        }

        return uint16(fee);
    }

    function _getEffectiveLiquidity(
        uint160 sqrtRatioX96Cache,
        uint160 sqrtRatioAX96Cache,
        uint160 sqrtRatioBX96Cache
    ) private view returns (uint128 effectiveLiquidity) {
        // Query current reserves
        // This already excludes poolManager and protocol fees
        (uint256 reserve0, uint256 reserve1) = ISovereignPool(pool).getReserves();

        uint128 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(sqrtRatioX96Cache, sqrtRatioBX96Cache, reserve0);
        uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96Cache, sqrtRatioX96Cache, reserve1);

        if (liquidity0 < liquidity1) {
            effectiveLiquidity = liquidity0;
        } else {
            effectiveLiquidity = liquidity1;
        }
    }

    function _ammSwap(
        ALMLiquidityQuoteInput memory almLiquidityQuoteInput,
        ALMLiquidityQuote memory liquidityQuote
    ) internal view returns (uint160 sqrtSpotPriceNewX96) {
        // Cache sqrt spot price
        uint160 sqrtPriceX96Cache = sqrtSpotPriceX96;
        // Cache sqrt price lower bound
        uint160 sqrtPriceLowX96Cache = sqrtPriceLowX96;
        // Cache sqrt price upper bound
        uint160 sqrtPriceHighX96Cache = sqrtPriceHighX96;

        // Calculate liquidity available to be utilized in this swap
        uint128 effectiveLiquidity = _getEffectiveLiquidity(
            sqrtPriceX96Cache,
            sqrtPriceLowX96Cache,
            sqrtPriceHighX96Cache
        );

        // Calculate tokenIn amount minus swap fee
        // Important: this assumes that pool applies 0 swap fee
        // which can be done by not whitelisting a swap fee module,
        // and keeping 0 as default constant fee
        // Therefore, the dynamic swap fee is calculated inside this Liquidity Module
        // via `_getAMMSwapFee()`
        uint256 amountInMinusFee = Math.mulDiv(almLiquidityQuoteInput.amountInMinusFee, 1e4 - _getAMMSwapFee(), 1e4);

        if (almLiquidityQuoteInput.isZeroToOne) {
            (sqrtSpotPriceNewX96, liquidityQuote.amountInFilled, liquidityQuote.amountOut, ) = SwapMath.computeSwapStep(
                sqrtPriceX96Cache,
                sqrtPriceLowX96Cache,
                effectiveLiquidity,
                amountInMinusFee.toInt256(), // always exact input swap
                0
            ); // fees have already been deducted
        } else {
            (sqrtSpotPriceNewX96, liquidityQuote.amountInFilled, liquidityQuote.amountOut, ) = SwapMath.computeSwapStep(
                sqrtPriceX96Cache,
                sqrtPriceHighX96Cache,
                effectiveLiquidity,
                amountInMinusFee.toInt256(), // always exact input swap
                0
            ); // fees have already been deducted
        }
        // Reserves are always kept in Sovereign Pool
        liquidityQuote.quoteFromPoolReserves = true;
    }

    function _solverSwap(
        ALMLiquidityQuoteInput memory almLiquidityQuoteInput,
        bytes memory externalContext,
        ALMLiquidityQuote memory liquidityQuote
    ) internal returns (uint160 sqrtSpotPriceNewX96) {
        (SolverOrderType memory sot, bytes memory signature) = abi.decode(externalContext, (SolverOrderType, bytes));

        // Execute SOT swap
        SwapState memory swapStateCache = swapState;

        SOTParams.validateBasicParams(
            sot.authorizedSender,
            sot.amountInMax,
            sot.amountOutMax,
            sot.signatureTimestamp,
            sot.expiry,
            almLiquidityQuoteInput.amountInMinusFee,
            almLiquidityQuoteInput.isZeroToOne ? maxToken1VolumeToQuote : maxToken0VolumeToQuote,
            swapStateCache.lastProcessedBlockTimestamp,
            swapStateCache.lastProcessedSignatureTimestamp
        );
        SOTParams.validateFeeParams(sot.feeMin, sot.feeGrowth, sot.feeMax, minAmmFee, minAmmFeeGrowth, maxAmmFeeGrowth);

        SOTParams.validatePriceBounds(
            almLiquidityQuoteInput.isZeroToOne
                ? Math.mulDiv(sot.amountOutMax, 1 << 192, sot.amountInMax).sqrt().toUint160()
                : Math.mulDiv(sot.amountInMax, 1 << 192, sot.amountOutMax).sqrt().toUint160(),
            sqrtSpotPriceX96,
            sot.sqrtSpotPriceX96New,
            _getSqrtOraclePriceX96(),
            sqrtPriceLowX96,
            sqrtPriceHighX96,
            oraclePriceMaxDiffBips,
            solverMaxDiscountBips
        );

        bytes32 sotHash = sot.hashStruct();
        if (!signer.isValidSignatureNow(_hashTypedDataV4(sotHash), signature)) {
            revert SOT__getLiquidityQuote_invalidSignature();
        }

        // Always true, since reserves must be stored in the pool
        liquidityQuote.quoteFromPoolReserves = true;
        liquidityQuote.amountOut = Math.mulDiv(
            almLiquidityQuoteInput.amountInMinusFee,
            sot.amountOutMax,
            sot.amountInMax
        );
        liquidityQuote.amountInFilled = almLiquidityQuoteInput.amountInMinusFee;

        // Update state
        // TODO: try to pack into one slot
        swapState = SwapState({
            lastProcessedBlockTimestamp: uint32(block.timestamp),
            lastProcessedSignatureTimestamp: sot.signatureTimestamp,
            lastProcessedFeeGrowth: sot.feeGrowth,
            lastProcessedFeeMin: sot.feeMin,
            lastProcessedFeeMax: sot.feeMax
        });
        sqrtSpotPriceNewX96 = sot.sqrtSpotPriceX96New;
    }
}
