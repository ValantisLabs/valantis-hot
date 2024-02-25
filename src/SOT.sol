// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

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
import { ISwapFeeModule, SwapFeeModuleData } from 'valantis-core/src/swap-fee-modules/interfaces/ISwapFeeModule.sol';

import { SOTParams } from 'src/libraries/SOTParams.sol';
import { TightPack } from 'src/libraries/utils/TightPack.sol';
import { LiquidityAmounts } from 'src/libraries/LiquidityAmounts.sol';
import { AlternatingNonceBitmap } from 'src/libraries/AlternatingNonceBitmap.sol';
import { SOTConstants } from 'src/libraries/SOTConstants.sol';
import {
    SolverOrderType,
    SolverWriteSlot,
    SolverReadSlot,
    SOTConstructorArgs,
    AMMState,
    AMMLiquidityState
} from 'src/structs/SOTStructs.sol';
import { SOTOracle } from 'src/SOTOracle.sol';

/**
    @title Solver Order Type.
    @notice Valantis Sovereign Liquidity Module.
 */
contract SOT is ISovereignALM, ISwapFeeModule, EIP712, SOTOracle {
    using Math for uint256;
    using SafeCast for uint256;
    using SignatureChecker for address;
    using SOTParams for SolverOrderType;
    using SafeERC20 for IERC20;
    using TightPack for AMMState;
    using AlternatingNonceBitmap for uint56;

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error SOT__onlyPool();
    error SOT__onlyManager();
    error SOT__onlyLiquidityProvider();
    error SOT__onlyUnpaused();
    error SOT__reentrant();
    error SOT__constructor_invalidFeeGrowthBounds();
    error SOT__constructor_invalidLiquidityProvider();
    error SOT__constructor_invalidMinAMMFee();
    error SOT__constructor_invalidManager();
    error SOT__constructor_invalidOraclePriceMaxDiffBips();
    error SOT__constructor_invalidSigner();
    error SOT__constructor_invalidSolverMaxDiscountBips();
    error SOT__constructor_invalidSovereignPool();
    error SOT__constructor_invalidSovereignPoolConfig();
    error SOT__constructor_invalidSqrtPriceBounds();
    error SOT__constructor_invalidToken0();
    error SOT__constructor_invalidToken1();
    error SOT__getLiquidityQuote_ammLocked();
    error SOT__getLiquidityQuote_invalidFeePath();
    error SOT__getLiquidityQuote_invalidSignature();
    error SOT__getLiquidityQuote_maxSolverQuotesExceeded();
    error SOT__getLiquidityQuote_zeroAmountOut();
    error SOT__setMaxAllowedQuotes_invalidMaxAllowedQuotes();
    error SOT__setSolverFeeInBips_invalidSolverFee();
    error SOT___checkSpotPriceRange_invalidSqrtSpotPriceX96(uint160 sqrtSpotPriceX96);

    /************************************************
     *  EVENTS
     ***********************************************/

    event ManagerUpdate(address indexed manager);
    event SignerUpdate(address indexed signer);
    event MaxTokenVolumeSet(uint256 amount0, uint256 amount1);
    event SolverFeeSet(uint16 fee0Bips, uint16 fee1Bips);
    event MaxAllowedQuoteSet(uint8 maxQuotes);
    event PauseSet(bool pause);
    event PriceBoundSet(uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96);
    event EffectiveAMMLiquidityUpdate(uint256 effectiveAMMLiquidity);
    event SpotPriceUpdate(uint160 sqrtSpotPriceX96);

    /************************************************
     *  IMMUTABLES
     ***********************************************/

    /**
	    @notice Sovereign Pool to which this Liquidity Module is bound.
    */
    address public immutable pool;

    /**
	    @notice Address of account which is meant to deposit & withdraw liquidity.
     */
    address public immutable liquidityProvider;

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
        Min Value: 0 %
        Max Value: 0.65535 % per second
        @dev SOT reverts if feeGrowthInPips exceeds these bounds.
     */
    uint16 public immutable minAMMFeeGrowthInPips;
    uint16 public immutable maxAMMFeeGrowthInPips;

    /**
	    @notice Minimum allowed AMM fee, in basis-points.
	    @dev SOT reverts if feeMinToken{0,1} is below this value.
     */
    uint16 public immutable minAMMFee;

    /************************************************
     *  STORAGE
     ***********************************************/

    /**
        @notice Tightly packed storage slots for:
            * sqrtSpotPriceX96 (a): AMM square-root spot price, in Q64.96 format.
            * sqrtPriceLowX96 (b): square-root lower price bound, in Q64.96 format.
            * sqrtPriceHighX96 (c): square-root upper price bound, in Q64.96 format.
        
        @dev sqrtSpotPriceX96, sqrtPriceLowX96, and sqrtPriceHighX96 values are packed into 2 slots.
            *slot1:
                <<  32 free bits | upper 64 bits of sqrtPriceLowX96 | 160 bits of sqrtSpotPriceX96 >>
            *slot2:
                << lower 96 bits  of sqrtPriceLowX96 | 160 bits of sqrtPriceHighX96 >>
 

        @dev sqrtSpotPriceX96 can only be updated on AMM swaps or after processing a valid SOT quote.
     */
    AMMState private _ammState;

    /**
        @notice Contains state variables which get updated on swaps. 
     */
    SolverWriteSlot public solverWriteSlot;

    /**
	    @notice Address of account which is meant to validate SOT quote signatures.
        @dev Can be updated by `manager`.
     */
    SolverReadSlot public solverReadSlot;

    /**
		@notice Account that manages all access controls to this liquidity module.
     */
    address public manager;

    /**
	    @notice Maximum amount of token{0,1} to quote to solvers on each SOT.
        @dev Can be updated by `manager`.
     */
    uint256 public maxToken0VolumeToQuote;
    uint256 public maxToken1VolumeToQuote;

    bool public isPaused;

    /**
        @notice Liquidity which gets utilized on AMM swaps. 
     */
    AMMLiquidityState private _ammLiquidityState;

    /************************************************
     *  MODIFIERS
     ***********************************************/

    modifier onlyPool() {
        _onlyPool();
        _;
    }

    modifier onlyManager() {
        _onlyManager();
        _;
    }

    modifier onlyLiquidityProvider() {
        _onlyLiquidityProvider();
        _;
    }

    modifier onlyUnpaused() {
        _onlyUnpaused();
        _;
    }

    modifier poolNonReentrant() {
        _poolNonReentrant();
        _;
    }

    /************************************************
     *  CONSTRUCTOR
     ***********************************************/

    constructor(
        SOTConstructorArgs memory _args
    )
        EIP712('Valantis Solver Order Type', '1')
        SOTOracle(
            ISovereignPool(_args.pool).token0(),
            ISovereignPool(_args.pool).token1(),
            _args.feedToken0,
            _args.feedToken1,
            _args.maxOracleUpdateDurationFeed0,
            _args.maxOracleUpdateDurationFeed1
        )
    {
        if (_args.pool == address(0)) {
            revert SOT__constructor_invalidSovereignPool();
        }

        // Sovereign Pool cannot have an external sovereignVault, nor a verifierModule
        bool isValidPoolConfig = (ISovereignPool(_args.pool).sovereignVault() == _args.pool) &&
            (ISovereignPool(_args.pool).verifierModule() == address(0));
        if (!isValidPoolConfig) {
            revert SOT__constructor_invalidSovereignPoolConfig();
        }

        pool = _args.pool;

        if (_args.manager == address(0)) {
            revert SOT__constructor_invalidManager();
        }

        manager = _args.manager;

        if (_args.signer == address(0)) {
            revert SOT__constructor_invalidSigner();
        }

        solverReadSlot.signer = _args.signer;

        if (_args.liquidityProvider == address(0)) {
            revert SOT__constructor_invalidLiquidityProvider();
        }

        liquidityProvider = _args.liquidityProvider;

        maxDelay = _args.maxDelay;

        if (_args.solverMaxDiscountBips > SOTConstants.BIPS) {
            revert SOT__constructor_invalidSolverMaxDiscountBips();
        }

        solverMaxDiscountBips = _args.solverMaxDiscountBips;

        if (_args.oraclePriceMaxDiffBips > SOTConstants.BIPS) {
            revert SOT__constructor_invalidOraclePriceMaxDiffBips();
        }

        oraclePriceMaxDiffBips = _args.oraclePriceMaxDiffBips;

        if (_args.minAMMFeeGrowthInPips > _args.maxAMMFeeGrowthInPips) {
            revert SOT__constructor_invalidFeeGrowthBounds();
        }
        minAMMFeeGrowthInPips = _args.minAMMFeeGrowthInPips;

        maxAMMFeeGrowthInPips = _args.maxAMMFeeGrowthInPips;

        if (_args.minAMMFee > SOTConstants.BIPS) {
            revert SOT__constructor_invalidMinAMMFee();
        }

        minAMMFee = _args.minAMMFee;

        SOTParams.validatePriceBounds(_args.sqrtSpotPriceX96, _args.sqrtPriceLowX96, _args.sqrtPriceHighX96);

        _ammState.setState(_args.sqrtSpotPriceX96, _args.sqrtPriceLowX96, _args.sqrtPriceHighX96);

        // AMM State is initialized as unpaused
    }

    /************************************************
     *  GETTER FUNCTIONS
     ***********************************************/

    /**
        @notice Returns active AMM liquidity (which gets utilized during AMM swaps).
     */
    function effectiveAMMLiquidity() external view poolNonReentrant returns (uint128) {
        return _ammLiquidityState.liquidity;
    }

    function isAMMUnlocked() external view poolNonReentrant returns (bool) {
        return _ammLiquidityState.isAMMUnlocked;
    }

    // @audit Verify that this function is safe from view-only reentrancy.
    /**
        @notice Returns square-root spot price, lower and upper bounds of the AMM position. 
     */
    function getAMMState()
        external
        view
        poolNonReentrant
        returns (uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96)
    {
        (sqrtSpotPriceX96, sqrtPriceLowX96, sqrtPriceHighX96) = _ammState.getState();
    }

    /**
        @notice Returns the AMM reserves assuming some AMM spot price.
        @param sqrtSpotPriceX96New square-root price to query AMM reserves for, in Q96 format.
        @return reserve0 Reserves of token0 at `sqrtSpotPriceX96New`.
        @return reserve1 Reserves of token1 at `sqrtSpotPriceX96New`.
     */
    function getReservesAtPrice(
        uint160 sqrtSpotPriceX96New
    ) external view poolNonReentrant returns (uint256 reserve0, uint256 reserve1) {
        (uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96) = _ammState.getState();

        (reserve0, reserve1) = ISovereignPool(pool).getReserves();

        (uint256 activeReserve0, uint256 activeReserve1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtSpotPriceX96,
            sqrtPriceLowX96,
            sqrtPriceHighX96,
            _ammLiquidityState.liquidity
        );

        uint256 passiveReserve0 = reserve0 - activeReserve0;
        uint256 passiveReserve1 = reserve1 - activeReserve1;

        (activeReserve0, activeReserve1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtSpotPriceX96New,
            sqrtPriceLowX96,
            sqrtPriceHighX96,
            _ammLiquidityState.liquidity
        );

        reserve0 = passiveReserve0 + activeReserve0;
        reserve1 = passiveReserve1 + activeReserve1;
    }

    /**
        @notice EIP-712 domain separator V4. 
     */
    function domainSeparatorV4() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /************************************************
     *  SETTER FUNCTIONS
     ***********************************************/

    /**
        @notice Changes the `manager` of this contract.
        @dev Only callable by `manager`.
        @dev It assumes that `manager` implements a timelock when calling this function.
     */
    function setManager(address _manager) external onlyManager {
        manager = _manager;

        emit ManagerUpdate(_manager);
    }

    /**
        @notice Changes the signer of the pool.
        @dev Only callable by `manager`.
        @dev It assumes that `manager` implements a timelock when calling this function.
     */
    function setSigner(address _signer) external onlyManager {
        solverReadSlot.signer = _signer;

        emit SignerUpdate(_signer);
    }

    /**
        @notice Changes the maximum token volumes available for a single SOT quote.
        @dev Only callable by `manager`.
        @dev It assumes that `manager` implements a timelock when calling this function.
     */
    function setMaxTokenVolumes(uint256 _maxToken0VolumeToQuote, uint256 _maxToken1VolumeToQuote) external onlyManager {
        maxToken0VolumeToQuote = _maxToken0VolumeToQuote;
        maxToken1VolumeToQuote = _maxToken1VolumeToQuote;

        emit MaxTokenVolumeSet(_maxToken0VolumeToQuote, _maxToken1VolumeToQuote);
    }

    /**
        @notice Changes the standard fee charged on all solver swaps.
        @dev Only callable by `manager`.
        @dev It assumes that `manager` implements a timelock when calling this function.
     */
    function setSolverFeeInBips(uint16 _solverFeeBipsToken0, uint16 _solverFeeBipsToken1) external onlyManager {
        if (
            _solverFeeBipsToken0 > SOTConstants.MAX_SOLVER_FEE_IN_BIPS ||
            _solverFeeBipsToken1 > SOTConstants.MAX_SOLVER_FEE_IN_BIPS
        ) {
            revert SOT__setSolverFeeInBips_invalidSolverFee();
        }

        solverReadSlot.solverFeeBipsToken0 = _solverFeeBipsToken0;
        solverReadSlot.solverFeeBipsToken1 = _solverFeeBipsToken1;

        emit SolverFeeSet(_solverFeeBipsToken0, _solverFeeBipsToken1);
    }

    /**
        @notice Updates the maximum number of SOT quotes allowed on a single block. 
        @dev Only callable by `manager`.
        @dev It assumes that `manager` implements a timelock when calling this function.
     */
    function setMaxAllowedQuotes(uint8 _maxAllowedQuotes) external onlyManager {
        if (_maxAllowedQuotes > SOTConstants.MAX_SOT_QUOTES_IN_BLOCK) {
            revert SOT__setMaxAllowedQuotes_invalidMaxAllowedQuotes();
        }

        solverReadSlot.maxAllowedQuotes = _maxAllowedQuotes;

        emit MaxAllowedQuoteSet(_maxAllowedQuotes);
    }

    /**
        @notice Updates the pause flag, which instantly pauses all critical functions except withdrawals.
        @dev Only callable by `manager`.
     */
    function setPause(bool _value) external onlyManager {
        isPaused = _value;
        emit PauseSet(_value);
    }

    /**
        @notice Sets the AMM position's square-root upper and lower price bounds.
        @param _sqrtPriceLowX96 New square-root lower price bound.
        @param _sqrtPriceHighX96 New square-root upper price bound.
        @param _expectedSqrtSpotPriceLowerX96 Lower limit for expected spot price (inclusive).
        @param _expectedSqrtSpotPriceUpperX96 Upper limit for expected spot price (inclusive).
        @dev Can be used to utilize disproportionate token liquidity by tuning price bounds offchain.
        @dev Only callable by `liquidityProvider`.
        @dev It assumes that `liquidityProvider` implements a timelock when calling this function.
     */
    function setPriceBounds(
        uint160 _sqrtPriceLowX96,
        uint160 _sqrtPriceHighX96,
        uint160 _expectedSqrtSpotPriceLowerX96,
        uint160 _expectedSqrtSpotPriceUpperX96
    ) external poolNonReentrant onlyLiquidityProvider {
        // Allow `liquidityProvider` to cross-check sqrt spot price against expected bounds,
        // to protect against its manipulation
        _checkSpotPriceRange(_expectedSqrtSpotPriceLowerX96, _expectedSqrtSpotPriceUpperX96);

        (uint160 sqrtSpotPriceX96Cache, , ) = _ammState.getState();

        // Check that new bounds are valid,
        // and do not exclude current spot price
        SOTParams.validatePriceBounds(sqrtSpotPriceX96Cache, _sqrtPriceLowX96, _sqrtPriceHighX96);

        _ammState.setState(sqrtSpotPriceX96Cache, _sqrtPriceLowX96, _sqrtPriceHighX96);

        emit PriceBoundSet(_sqrtPriceLowX96, _sqrtPriceHighX96);

        // Update AMM liquidity with new price bounds
        _updateAMMLiquidity();

        _ammLiquidityState.isAMMUnlocked = true;
    }

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

    // @audit Verify that we don't need a reentrancy guard for getLiquidityQuote/deposit/withdraw
    function getLiquidityQuote(
        ALMLiquidityQuoteInput memory _almLiquidityQuoteInput,
        bytes calldata _externalContext,
        bytes calldata /*_verifierData*/
    ) external override onlyPool onlyUnpaused returns (ALMLiquidityQuote memory liquidityQuote) {
        if (_externalContext.length == 0) {
            if (!_ammLiquidityState.isAMMUnlocked) {
                revert SOT__getLiquidityQuote_ammLocked();
            }
            // AMM Swap
            _ammSwap(_almLiquidityQuoteInput, liquidityQuote);
        } else {
            // Solver Swap
            _solverSwap(_almLiquidityQuoteInput, _externalContext, liquidityQuote);

            // Solver swap needs a swap callback, to update AMM liquidity correctly
            liquidityQuote.isCallbackOnSwap = true;
        }

        if (liquidityQuote.amountOut == 0) {
            revert SOT__getLiquidityQuote_zeroAmountOut();
        }

        _ammLiquidityState.isAMMUnlocked = true;
    }

    // @audit: Do we need a reentrancy guard here?
    function depositLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        uint160 _expectedSqrtSpotPriceLowerX96,
        uint160 _expectedSqrtSpotPriceUpperX96
    ) external onlyLiquidityProvider onlyUnpaused returns (uint256 amount0Deposited, uint256 amount1Deposited) {
        // Allow `liquidityProvider` to cross-check sqrt spot price against expected bounds,
        // to protect against its manipulation
        _checkSpotPriceRange(_expectedSqrtSpotPriceLowerX96, _expectedSqrtSpotPriceUpperX96);

        (amount0Deposited, amount1Deposited) = ISovereignPool(pool).depositLiquidity(
            _amount0,
            _amount1,
            liquidityProvider,
            '',
            ''
        );

        // Update AMM liquidity with post-deposit reserves
        _updateAMMLiquidity();

        _ammLiquidityState.isAMMUnlocked = false;
    }

    // @audit: Do we need a reentrancy guard here?
    function withdrawLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        address _recipient,
        uint160 _expectedSqrtSpotPriceLowerX96,
        uint160 _expectedSqrtSpotPriceUpperX96
    ) external onlyLiquidityProvider {
        // Allow `liquidityProvider` to cross-check sqrt spot price against expected bounds,
        // to protect against its manipulation
        _checkSpotPriceRange(_expectedSqrtSpotPriceLowerX96, _expectedSqrtSpotPriceUpperX96);

        ISovereignPool(pool).withdrawLiquidity(_amount0, _amount1, liquidityProvider, _recipient, '');

        // Update AMM liquidity with post-withdrawal reserves
        _updateAMMLiquidity();

        _ammLiquidityState.isAMMUnlocked = false;
    }

    function getSwapFeeInBips(
        bool _isZeroToOne,
        uint256 /**_amountIn*/,
        address /**_user*/,
        bytes memory _swapFeeModuleContext
    ) external view returns (SwapFeeModuleData memory swapFeeModuleData) {
        // Verification of branches is done during getLiquidityQuote
        if (_swapFeeModuleContext.length != 0) {
            // Solver Branch
            swapFeeModuleData.feeInBips = _isZeroToOne
                ? solverReadSlot.solverFeeBipsToken0
                : solverReadSlot.solverFeeBipsToken1;
        } else {
            // AMM Branch
            swapFeeModuleData.feeInBips = _getAMMFeeInBips(_isZeroToOne);
        }
    }

    function callbackOnSwapEnd(
        uint256 /*_effectiveFee*/,
        int24 /*_spotPriceTick*/,
        uint256 /*_amountInUsed*/,
        uint256 /*_amountOut*/,
        SwapFeeModuleData memory /*_swapFeeModuleData*/
    ) external {
        // Fee Module callback for Universal Pool (not needed here)
    }

    function callbackOnSwapEnd(
        uint256 /*_effectiveFee*/,
        uint256 /*_amountInUsed*/,
        uint256 /*_amountOut*/,
        SwapFeeModuleData memory /*_swapFeeModuleData*/
    ) external {
        // Fee Module callback for Sovereign Pool (not needed here)
    }

    function onDepositLiquidityCallback(
        uint256 _amount0,
        uint256 _amount1,
        bytes memory /*_data*/
    ) external override onlyPool {
        if (_amount0 > 0) {
            address token0 = ISovereignPool(pool).token0();
            IERC20(token0).safeTransferFrom(liquidityProvider, msg.sender, _amount0);
        }

        if (_amount1 > 0) {
            address token1 = ISovereignPool(pool).token1();
            IERC20(token1).safeTransferFrom(liquidityProvider, msg.sender, _amount1);
        }
    }

    function onSwapCallback(
        bool /*_isZeroToOne*/,
        uint256 /*_amountIn*/,
        uint256 /*_amountOut*/
    ) external override onlyPool {
        _updateAMMLiquidity();
    }

    /************************************************
     *  INTERNAL FUNCTIONS
     ***********************************************/

    function _getAMMFeeInBips(bool isZeroToOne) internal view returns (uint32 feeInBips) {
        SolverWriteSlot memory solverWriteSlotCache = solverWriteSlot;

        uint16 feeMin = isZeroToOne ? solverWriteSlotCache.feeMinToken0 : solverWriteSlotCache.feeMinToken1;
        uint16 feeMax = isZeroToOne ? solverWriteSlotCache.feeMaxToken0 : solverWriteSlotCache.feeMaxToken1;
        uint16 feeGrowthInPips = isZeroToOne
            ? solverWriteSlotCache.feeGrowthInPipsToken0
            : solverWriteSlotCache.feeGrowthInPipsToken1;

        feeInBips =
            uint32(feeMin) +
            Math
                .mulDiv(feeGrowthInPips, (block.timestamp - solverWriteSlotCache.lastProcessedSignatureTimestamp), 100)
                .toUint32();

        // Cap fee if necessary
        if (feeInBips > uint32(feeMax)) {
            feeInBips = uint32(feeMax);
        }
    }

    function _ammSwap(
        ALMLiquidityQuoteInput memory almLiquidityQuoteInput,
        ALMLiquidityQuote memory liquidityQuote
    ) internal {
        // Check that the fee path was chosen correctly
        if (almLiquidityQuoteInput.feeInBips != _getAMMFeeInBips(almLiquidityQuoteInput.isZeroToOne)) {
            revert SOT__getLiquidityQuote_invalidFeePath();
        }

        // Cache sqrt spot price, lower bound, and upper bound
        (uint160 sqrtSpotPriceX96Cache, uint160 sqrtPriceLowX96Cache, uint160 sqrtPriceHighX96Cache) = _ammState
            .getState();

        // Calculate amountOut according to CPMM math
        uint160 sqrtSpotPriceX96New;
        (sqrtSpotPriceX96New, liquidityQuote.amountInFilled, liquidityQuote.amountOut, ) = SwapMath.computeSwapStep(
            sqrtSpotPriceX96Cache,
            almLiquidityQuoteInput.isZeroToOne ? sqrtPriceLowX96Cache : sqrtPriceHighX96Cache,
            _ammLiquidityState.liquidity,
            almLiquidityQuoteInput.amountInMinusFee.toInt256(), // always exact input swap
            0 // fees have already been deducted
        );

        _ammState.setSqrtSpotPriceX96(sqrtSpotPriceX96New);
        emit SpotPriceUpdate(sqrtSpotPriceX96New);
    }

    function _solverSwap(
        ALMLiquidityQuoteInput memory almLiquidityQuoteInput,
        bytes memory externalContext,
        ALMLiquidityQuote memory liquidityQuote
    ) internal {
        // @audit Verify if this is safe ( more info in SOTConcrete.t.sol with @audit tag)
        (SolverOrderType memory sot, bytes memory signature) = abi.decode(externalContext, (SolverOrderType, bytes));

        // Execute SOT swap
        SolverWriteSlot memory solverWriteSlotCache = solverWriteSlot;
        SolverReadSlot memory solverReadSlotCache = solverReadSlot;

        // Check that the fee path was chosen correctly
        if (
            almLiquidityQuoteInput.feeInBips !=
            (
                almLiquidityQuoteInput.isZeroToOne
                    ? solverReadSlotCache.solverFeeBipsToken0
                    : solverReadSlotCache.solverFeeBipsToken1
            )
        ) {
            revert SOT__getLiquidityQuote_invalidFeePath();
        }

        // An SOT only updates state if:
        // 1. It is the first SOT that updates state in the block.
        // 2. It was signed after the last processed signature timestamp.
        bool isDiscountedSolver = block.timestamp > solverWriteSlotCache.lastStateUpdateTimestamp &&
            (solverWriteSlotCache.lastProcessedSignatureTimestamp < sot.signatureTimestamp);

        uint8 quotesInCurrentBlock = block.timestamp > solverWriteSlotCache.lastProcessedQuoteTimestamp
            ? 1
            : solverWriteSlotCache.lastProcessedBlockQuoteCount + 1;

        if (quotesInCurrentBlock > solverReadSlotCache.maxAllowedQuotes) {
            revert SOT__getLiquidityQuote_maxSolverQuotesExceeded();
        }

        uint256 solverPriceX192 = isDiscountedSolver ? sot.solverPriceX192Discounted : sot.solverPriceX192Base;

        // Calculate the amountOut according to the quoted price
        liquidityQuote.amountOut = almLiquidityQuoteInput.isZeroToOne
            ? Math.mulDiv(almLiquidityQuoteInput.amountInMinusFee, solverPriceX192, SOTConstants.Q192)
            : Math.mulDiv(almLiquidityQuoteInput.amountInMinusFee, SOTConstants.Q192, solverPriceX192);
        liquidityQuote.amountInFilled = almLiquidityQuoteInput.amountInMinusFee;

        sot.validateFeeParams(minAMMFee, minAMMFeeGrowthInPips, maxAMMFeeGrowthInPips);

        sot.validateBasicParams(
            liquidityQuote.amountOut,
            almLiquidityQuoteInput.sender,
            almLiquidityQuoteInput.recipient,
            almLiquidityQuoteInput.amountInMinusFee,
            almLiquidityQuoteInput.isZeroToOne ? maxToken1VolumeToQuote : maxToken0VolumeToQuote,
            maxDelay,
            solverWriteSlotCache.alternatingNonceBitmap
        );

        SOTParams.validatePriceConsistency(
            _ammState,
            solverPriceX192.sqrt().toUint160(),
            sot.sqrtSpotPriceX96New,
            getSqrtOraclePriceX96(),
            oraclePriceMaxDiffBips,
            solverMaxDiscountBips
        );

        // Verify SOT quote signature
        // @audit: Verify that this is a safe way to check signatures
        // @TODO: @audit: Verify that the typehash is correct in the SOTConstants file
        bytes32 sotHash = sot.hashParams();
        if (!solverReadSlotCache.signer.isValidSignatureNow(_hashTypedDataV4(sotHash), signature)) {
            revert SOT__getLiquidityQuote_invalidSignature();
        }

        // Only update the pool state, if this is a discounted solver quote
        if (isDiscountedSolver) {
            solverWriteSlot = SolverWriteSlot({
                lastProcessedBlockQuoteCount: quotesInCurrentBlock,
                feeGrowthInPipsToken0: sot.feeGrowthInPipsToken0,
                feeMaxToken0: sot.feeMaxToken0,
                feeMinToken0: sot.feeMinToken0,
                feeGrowthInPipsToken1: sot.feeGrowthInPipsToken1,
                feeMaxToken1: sot.feeMaxToken1,
                feeMinToken1: sot.feeMinToken1,
                lastStateUpdateTimestamp: block.timestamp.toUint32(),
                lastProcessedQuoteTimestamp: block.timestamp.toUint32(),
                lastProcessedSignatureTimestamp: sot.signatureTimestamp,
                alternatingNonceBitmap: solverWriteSlotCache.alternatingNonceBitmap.flipNonce(sot.nonce)
            });

            _ammState.setSqrtSpotPriceX96(sot.sqrtSpotPriceX96New);
            emit SpotPriceUpdate(sot.sqrtSpotPriceX96New);
        } else {
            solverWriteSlotCache.lastProcessedBlockQuoteCount = quotesInCurrentBlock;
            solverWriteSlotCache.lastProcessedQuoteTimestamp = block.timestamp.toUint32();
            solverWriteSlotCache.alternatingNonceBitmap = solverWriteSlotCache.alternatingNonceBitmap.flipNonce(
                sot.nonce
            );

            solverWriteSlot = solverWriteSlotCache;
        }
    }

    /************************************************
     *  PRIVATE FUNCTIONS
     ***********************************************/

    function _updateAMMLiquidity() private {
        (uint160 sqrtSpotPriceX96Cache, uint160 sqrtPriceLowX96Cache, uint160 sqrtPriceHighX96Cache) = _ammState
            .getState();

        // Query current reserves
        (uint256 reserve0, uint256 reserve1) = ISovereignPool(pool).getReserves();

        uint128 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
            sqrtSpotPriceX96Cache,
            sqrtPriceHighX96Cache,
            reserve0
        );
        uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
            sqrtPriceLowX96Cache,
            sqrtSpotPriceX96Cache,
            reserve1
        );

        if (liquidity0 < liquidity1) {
            _ammLiquidityState.liquidity = liquidity0;
            emit EffectiveAMMLiquidityUpdate(liquidity0);
        } else {
            _ammLiquidityState.liquidity = liquidity1;
            emit EffectiveAMMLiquidityUpdate(liquidity1);
        }
    }

    /**
        @notice Checks that the current AMM spot price is within the expected range.
        @param _expectedSqrtSpotPriceLowerX96 Lower limit for expected spot price. ( inclusive )
        @param _expectedSqrtSpotPriceUpperX96 Upper limit for expected spot price. ( inclusive )
        @dev If both `_expectedSqrtSpotPriceLowerX96` and `_expectedSqrtSpotPriceUpperX96` are 0,
             then no check is performed.
      */
    function _checkSpotPriceRange(
        uint160 _expectedSqrtSpotPriceLowerX96,
        uint160 _expectedSqrtSpotPriceUpperX96
    ) private view {
        bool checkSqrtSpotPriceAbsDiff = _expectedSqrtSpotPriceUpperX96 != 0 || _expectedSqrtSpotPriceLowerX96 != 0;
        if (checkSqrtSpotPriceAbsDiff) {
            uint160 sqrtSpotPriceX96 = _ammState.getSqrtSpotPriceX96();

            // Check that spot price has not been manipulated
            if (
                sqrtSpotPriceX96 > _expectedSqrtSpotPriceUpperX96 || sqrtSpotPriceX96 < _expectedSqrtSpotPriceLowerX96
            ) {
                revert SOT___checkSpotPriceRange_invalidSqrtSpotPriceX96(sqrtSpotPriceX96);
            }
        }
    }

    function _onlyPool() private view {
        if (msg.sender != pool) {
            revert SOT__onlyPool();
        }
    }

    function _onlyManager() private view {
        if (msg.sender != manager) {
            revert SOT__onlyManager();
        }
    }

    function _onlyUnpaused() private view {
        if (isPaused) {
            revert SOT__onlyUnpaused();
        }
    }

    function _onlyLiquidityProvider() private view {
        if (msg.sender != liquidityProvider) {
            revert SOT__onlyLiquidityProvider();
        }
    }

    function _poolNonReentrant() private view {
        if (ISovereignPool(pool).isLocked()) {
            revert SOT__reentrant();
        }
    }
}
