// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import { SwapMath } from '../lib/v3-core/contracts/libraries/SwapMath.sol';
import { LiquidityAmounts } from '../lib/v3-periphery/contracts/libraries/LiquidityAmounts.sol';

import { IERC20 } from '../lib/valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '../lib/valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import { EIP712 } from '../lib/valantis-core/lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol';
import { Math } from '../lib/valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { SafeCast } from '../lib/valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {
    SignatureChecker
} from '../lib/valantis-core/lib/openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';
import {
    ISovereignALM,
    ALMLiquidityQuote,
    ALMLiquidityQuoteInput
} from '../lib/valantis-core/src/alm/interfaces/ISovereignALM.sol';
import { ISovereignPool } from '../lib/valantis-core/src/pools/interfaces/ISovereignPool.sol';
import {
    ISwapFeeModuleMinimal,
    SwapFeeModuleData
} from '../lib/valantis-core/src/swap-fee-modules/interfaces/ISwapFeeModule.sol';

import { ReserveMath } from './libraries/ReserveMath.sol';
import { HOTParams } from './libraries/HOTParams.sol';
import { TightPack } from './libraries/utils/TightPack.sol';
import { AlternatingNonceBitmap } from './libraries/AlternatingNonceBitmap.sol';
import { HOTConstants } from './libraries/HOTConstants.sol';
import { HybridOrderType, HotWriteSlot, HotReadSlot, HOTConstructorArgs, AMMState } from './structs/HOTStructs.sol';
import { HOTOracle } from './HOTOracle.sol';
import { IHOT } from './interfaces/IHOT.sol';

/**
    @title Hybrid Order Type.
    @notice Valantis Sovereign Liquidity Module.
 */
contract HOT is ISovereignALM, ISwapFeeModuleMinimal, IHOT, EIP712, HOTOracle {
    using Math for uint256;
    using SafeCast for uint256;
    using SignatureChecker for address;
    using HOTParams for HybridOrderType;
    using SafeERC20 for IERC20;
    using TightPack for AMMState;
    using AlternatingNonceBitmap for uint56;

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error HOT__onlyPool();
    error HOT__onlyManager();
    error HOT__onlyLiquidityProvider();
    error HOT__onlyUnpaused();
    error HOT__poolReentrant();
    error HOT__constructor_invalidFeeGrowthBounds();
    error HOT__constructor_invalidLiquidityProvider();
    error HOT__constructor_invalidMinAMMFee();
    error HOT__constructor_invalidManager();
    error HOT__constructor_invalidOraclePriceMaxDiffBips();
    error HOT__constructor_invalidSigner();
    error HOT__constructor_invalidHotMaxDiscountBips();
    error HOT__constructor_invalidSovereignPoolConfig();
    error HOT__depositLiquidity_spotPriceAndOracleDeviation();
    error HOT__getLiquidityQuote_invalidFeePath();
    error HOT__getLiquidityQuote_zeroAmountOut();
    error HOT__proposedFeeds_proposedFeedsAlreadySet();
    error HOT__setMaxAllowedQuotes_invalidMaxAllowedQuotes();
    error HOT__setMaxOracleDeviationBips_exceedsMaxDeviationBounds();
    error HOT__setPriceBounds_spotPriceAndOracleDeviation();
    error HOT__setHotFeeInBips_invalidHotFee();
    error HOT___checkSpotPriceRange_invalidBounds();
    error HOT___checkSpotPriceRange_invalidSqrtSpotPriceX96(uint160 sqrtSpotPriceX96);
    error HOT___ammSwap_invalidSpotPriceAfterSwap();
    error HOT___hotSwap_invalidSignature();
    error HOT___hotSwap_maxHotQuotesExceeded();

    /************************************************
     *  IMMUTABLES
     ***********************************************/

    /**
	    @notice Sovereign Pool to which this Liquidity Module is bound.
    */
    address internal immutable _pool;

    /**
	    @notice Address of account which is meant to deposit & withdraw liquidity.
     */
    address internal immutable _liquidityProvider;

    /**
	    @notice Maximum delay, in seconds, for acceptance of HOT quotes.
    */
    uint32 internal immutable _maxDelay;

    /**
	    @notice Maximum price discount allowed for HOT quotes,
                expressed in basis-points.
    */
    uint16 internal immutable _hotMaxDiscountBipsLower;
    uint16 internal immutable _hotMaxDiscountBipsUpper;

    /**
	    @notice Maximum allowed relative deviation
                between sqrt spot price and sqrt oracle price,
                expressed in basis-points.
     */
    uint16 internal immutable _maxOracleDeviationBound;

    /**
	    @notice Bounds the growth rate, in basis-points, of the AMM fee 
					as time increases between last processed quote.
        Min Value: 0 %
        Max Value: 6.5535 % per second
        @dev 1 unit of feeGrowthE6 = 1/100th of 1 BIPS = 1/10000 of 1%.
        @dev HOT reverts if feeGrowthE6 exceeds these bounds.
     */
    uint16 internal immutable _minAMMFeeGrowthE6;
    uint16 internal immutable _maxAMMFeeGrowthE6;

    /**
	    @notice Minimum allowed AMM fee, in basis-points.
	    @dev HOT reverts if feeMinToken{0,1} is below this value.
     */
    uint16 internal immutable _minAMMFee;

    /************************************************
     *  STORAGE
     ***********************************************/
    /**
        @notice Active AMM Liquidity (which gets utilized during AMM swaps).
     */
    uint128 private _effectiveAMMLiquidity;

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
 

        @dev sqrtSpotPriceX96 can only be updated on AMM swaps or after processing a valid HOT quote.
     */
    AMMState private _ammState;

    /**
        @notice Contains state variables which get updated on swaps. 
     */
    HotWriteSlot public hotWriteSlot;

    /**
	    @notice Address of account which is meant to validate HOT quote signatures.
        @dev Can be updated by `manager`.
     */
    HotReadSlot public hotReadSlot;

    /**
		@notice Account that manages all access controls to this liquidity module.
     */
    address public manager;

    /**
	    @notice Maximum amount of token{0,1} to quote to solvers on each HOT.
        @dev Can be updated by `manager`.
     */
    uint256 internal _maxToken0VolumeToQuote;
    uint256 internal _maxToken1VolumeToQuote;

    /**
	    @notice If feeds are not set during deployment, then manager can propose feeds, once after deployment.
        @dev Can be updated by `manager`.
     */
    address public proposedFeedToken0;
    address public proposedFeedToken1;

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
        HOTConstructorArgs memory _args
    )
        EIP712('Valantis HOT', '1')
        HOTOracle(
            ISovereignPool(_args.pool).token0(),
            ISovereignPool(_args.pool).token1(),
            _args.feedToken0,
            _args.feedToken1,
            _args.maxOracleUpdateDurationFeed0,
            _args.maxOracleUpdateDurationFeed1
        )
    {
        // Sovereign Pool cannot have an external sovereignVault, nor a verifierModule
        bool isValidPoolConfig = (ISovereignPool(_args.pool).sovereignVault() == _args.pool) &&
            (ISovereignPool(_args.pool).verifierModule() == address(0));
        if (!isValidPoolConfig) {
            revert HOT__constructor_invalidSovereignPoolConfig();
        }

        _pool = _args.pool;

        if (_args.manager == address(0)) {
            revert HOT__constructor_invalidManager();
        }

        manager = _args.manager;

        if (_args.signer == address(0)) {
            revert HOT__constructor_invalidSigner();
        }

        hotReadSlot.signer = _args.signer;

        if (_args.liquidityProvider == address(0)) {
            revert HOT__constructor_invalidLiquidityProvider();
        }

        _liquidityProvider = _args.liquidityProvider;

        _maxDelay = _args.maxDelay;

        if (
            _args.hotMaxDiscountBipsLower > _args.maxOracleDeviationBound ||
            _args.hotMaxDiscountBipsUpper > _args.maxOracleDeviationBound
        ) {
            revert HOT__constructor_invalidHotMaxDiscountBips();
        }

        _hotMaxDiscountBipsLower = _args.hotMaxDiscountBipsLower;
        _hotMaxDiscountBipsUpper = _args.hotMaxDiscountBipsUpper;

        if (_args.maxOracleDeviationBound > HOTConstants.BIPS) {
            revert HOT__constructor_invalidOraclePriceMaxDiffBips();
        }

        _maxOracleDeviationBound = _args.maxOracleDeviationBound;

        if (_args.minAMMFeeGrowthE6 > _args.maxAMMFeeGrowthE6) {
            revert HOT__constructor_invalidFeeGrowthBounds();
        }
        _minAMMFeeGrowthE6 = _args.minAMMFeeGrowthE6;

        _maxAMMFeeGrowthE6 = _args.maxAMMFeeGrowthE6;

        if (_args.minAMMFee > HOTConstants.BIPS) {
            revert HOT__constructor_invalidMinAMMFee();
        }

        _minAMMFee = _args.minAMMFee;

        HOTParams.validatePriceBounds(_args.sqrtSpotPriceX96, _args.sqrtPriceLowX96, _args.sqrtPriceHighX96);

        _ammState.setState(_args.sqrtSpotPriceX96, _args.sqrtPriceLowX96, _args.sqrtPriceHighX96);

        emit ALMDeployed('HOT V1', address(this), address(_pool));

        // AMM State is initialized as unpaused
    }

    /************************************************
     *  GETTER FUNCTIONS
     ***********************************************/

    /**
        @notice Returns all immutable values of the HOT.
        @return pool Sovereign Pool address.
        @return liquidityProvider Liquidity provider address.
        @return maxDelay Maximum delay, in seconds, for acceptance of HOT quotes.
        @return hotMaxDiscountBipsLower Maximum discount allowed for HOT quotes.
        @return hotMaxDiscountBipsUpper Maximum discount allowed for HOT quotes.
        @return maxOracleDeviationBound Maximum allowed deviation between AMM and oracle price.
        @return minAMMFeeGrowthE6 Minimum AMM fee growth rate.
        @return maxAMMFeeGrowthE6 Maximum AMM fee growth rate.
        @return minAMMFee Minimum AMM fee.
     */
    function immutables()
        external
        view
        returns (
            address pool,
            address liquidityProvider,
            uint32 maxDelay,
            uint16 hotMaxDiscountBipsLower,
            uint16 hotMaxDiscountBipsUpper,
            uint16 maxOracleDeviationBound,
            uint16 minAMMFeeGrowthE6,
            uint16 maxAMMFeeGrowthE6,
            uint16 minAMMFee
        )
    {
        return (
            _pool,
            _liquidityProvider,
            _maxDelay,
            _hotMaxDiscountBipsLower,
            _hotMaxDiscountBipsUpper,
            _maxOracleDeviationBound,
            _minAMMFeeGrowthE6,
            _maxAMMFeeGrowthE6,
            _minAMMFee
        );
    }

    /**
        @notice Returns active AMM liquidity (which gets utilized during AMM swaps).
     */
    function effectiveAMMLiquidity() external view poolNonReentrant returns (uint128) {
        return _effectiveAMMLiquidity;
    }

    /**
        @notice Returns square-root spot price, lower and upper bounds of the AMM position. 
     */
    function getAMMState()
        external
        view
        poolNonReentrant
        returns (uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96)
    {
        (sqrtSpotPriceX96, sqrtPriceLowX96, sqrtPriceHighX96) = _getAMMState();
    }

    /**
        @notice Returns the AMM reserves assuming some AMM spot price.
        @param sqrtSpotPriceX96New square-root price to query AMM reserves for, in Q96 format.
        @return reserve0 Reserves of token0 at `sqrtSpotPriceX96New`.
        @return reserve1 Reserves of token1 at `sqrtSpotPriceX96New`.
     */
    function getReservesAtPrice(uint160 sqrtSpotPriceX96New) external view poolNonReentrant returns (uint256, uint256) {
        uint128 effectiveAMMLiquidityCache = _effectiveAMMLiquidity;

        uint128 calculatedLiquidity = _calculateAMMLiquidity();

        if (calculatedLiquidity < effectiveAMMLiquidityCache) {
            effectiveAMMLiquidityCache = calculatedLiquidity;
        }

        return ReserveMath.getReservesAtPrice(_ammState, _pool, effectiveAMMLiquidityCache, sqrtSpotPriceX96New);
    }

    /**
        @notice Returns the maximum token volumes allowed to be swapped in a single HOT quote.
        @return maxToken0VolumeToQuote Maximum token0 volume.
        @return maxToken1VolumeToQuote Maximum token1 volume.
     */
    function maxTokenVolumes() external view override returns (uint256, uint256) {
        return (_maxToken0VolumeToQuote, _maxToken1VolumeToQuote);
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
        hotReadSlot.signer = _signer;

        emit SignerUpdate(_signer);
    }

    /**
        @notice Propose the feeds for token{0,1}.
        @dev Only callable by `manager`.
        @dev It assumes that `manager` implements a timelock when calling this function.
        @dev Feeds can only be set once, and both should have non-zero values.
     */
    function proposeFeeds(address _feedToken0, address _feedToken1) external onlyManager {
        if (proposedFeedToken0 != address(0) || proposedFeedToken1 != address(0)) {
            revert HOT__proposedFeeds_proposedFeedsAlreadySet();
        }

        proposedFeedToken0 = _feedToken0;
        proposedFeedToken1 = _feedToken1;

        emit OracleFeedsProposed(_feedToken0, _feedToken1);
    }

    /**
        @notice Changes the maximum token volumes available for a single HOT quote.
        @dev Only callable by `manager`.
        @dev It assumes that `manager` implements a timelock when calling this function.
     */
    function setMaxTokenVolumes(uint256 maxToken0VolumeToQuote, uint256 maxToken1VolumeToQuote) external onlyManager {
        _maxToken0VolumeToQuote = maxToken0VolumeToQuote;
        _maxToken1VolumeToQuote = maxToken1VolumeToQuote;

        emit MaxTokenVolumeSet(maxToken0VolumeToQuote, maxToken1VolumeToQuote);
    }

    /**
        @notice Changes the standard fee charged on all hot swaps.
        @dev Only callable by `manager`.
        @dev It assumes that `manager` implements a timelock when calling this function.
     */
    function setHotFeeInBips(uint16 _hotFeeBipsToken0, uint16 _hotFeeBipsToken1) external onlyManager {
        if (
            _hotFeeBipsToken0 > HOTConstants.MAX_HOT_FEE_IN_BIPS || _hotFeeBipsToken1 > HOTConstants.MAX_HOT_FEE_IN_BIPS
        ) {
            revert HOT__setHotFeeInBips_invalidHotFee();
        }

        hotReadSlot.hotFeeBipsToken0 = _hotFeeBipsToken0;
        hotReadSlot.hotFeeBipsToken1 = _hotFeeBipsToken1;

        emit HotFeeSet(_hotFeeBipsToken0, _hotFeeBipsToken1);
    }

    /**
        @notice Updates the maximum number of HOT quotes allowed on a single block. 
        @dev Only callable by `manager`.
        @dev It assumes that `manager` implements a timelock when calling this function.
     */
    function setMaxAllowedQuotes(uint8 _maxAllowedQuotes) external onlyManager {
        if (_maxAllowedQuotes > HOTConstants.MAX_HOT_QUOTES_IN_BLOCK) {
            revert HOT__setMaxAllowedQuotes_invalidMaxAllowedQuotes();
        }

        hotReadSlot.maxAllowedQuotes = _maxAllowedQuotes;

        emit MaxAllowedQuoteSet(_maxAllowedQuotes);
    }

    /**
        @notice Sets the maximum allowed deviation between AMM and oracle price.
        @param _maxOracleDeviationBipsLower New maximum deviation in basis-points when sqrtSpotPrice < sqrtOraclePrice.
        @param _maxOracleDeviationBipsUpper New maximum deviation in basis-points when sqrtSpotPrice >= sqrtOraclePrice.
        @dev Only callable by `liquidityProvider`.
        @dev It assumes that `liquidityProvider` implements a timelock when calling this function.
     */
    function setMaxOracleDeviationBips(
        uint16 _maxOracleDeviationBipsLower,
        uint16 _maxOracleDeviationBipsUpper
    ) external onlyManager {
        if (
            _maxOracleDeviationBipsLower > _maxOracleDeviationBound ||
            _maxOracleDeviationBipsUpper > _maxOracleDeviationBound
        ) {
            revert HOT__setMaxOracleDeviationBips_exceedsMaxDeviationBounds();
        }

        hotReadSlot.maxOracleDeviationBipsLower = _maxOracleDeviationBipsLower;
        hotReadSlot.maxOracleDeviationBipsUpper = _maxOracleDeviationBipsUpper;

        emit MaxOracleDeviationBipsSet(_maxOracleDeviationBipsLower, _maxOracleDeviationBipsUpper);
    }

    /**
        @notice Updates the pause flag, which instantly pauses all critical functions except withdrawals.
        @dev Only callable by `manager`.
     */
    function setPause(bool _value) external onlyManager {
        hotReadSlot.isPaused = _value;

        emit PauseSet(_value);
    }

    /**
        @notice Sets the oracle feeds for token{0,1} to the proposed feeds set by manager.
        The oracle feeds should be set to 0, and the manager should have proposed valid non zero fields.
        @dev Only callable by `liquidityProvider`.
     */
    function setFeeds() external onlyLiquidityProvider {
        _setFeeds(proposedFeedToken0, proposedFeedToken1);

        emit OracleFeedsSet();
    }

    /**
        @notice Sets the AMM position's square-root upper and lower price bounds.
        @param _sqrtPriceLowX96 New square-root lower price bound.
        @param _sqrtPriceHighX96 New square-root upper price bound.
        @param _expectedSqrtSpotPriceLowerX96 Lower limit for expected spot price (inclusive).
        @param _expectedSqrtSpotPriceUpperX96 Upper limit for expected spot price (inclusive).
        @dev Can be used to utilize disproportionate token liquidity by tuning price bounds offchain.
        @dev Only callable by `liquidityProvider`.
        @dev It is recommended that `liquidityProvider` implements a timelock when calling this function.
        @dev It assumes that `liquidityProvider` implements sufficient internal protection against
             sandwich attacks, slippage checks or other types of spot price manipulation.
     */
    function setPriceBounds(
        uint160 _sqrtPriceLowX96,
        uint160 _sqrtPriceHighX96,
        uint160 _expectedSqrtSpotPriceLowerX96,
        uint160 _expectedSqrtSpotPriceUpperX96
    ) external poolNonReentrant onlyLiquidityProvider {
        // Allow `liquidityProvider` to cross-check sqrt spot price against expected bounds,
        // to protect against its manipulation
        uint160 sqrtSpotPriceX96Cache = _checkSpotPriceRange(
            _expectedSqrtSpotPriceLowerX96,
            _expectedSqrtSpotPriceUpperX96
        );

        HotReadSlot memory hotReadSlotCache = hotReadSlot;

        // It is sufficient to check only feedToken0, because either both of the feeds are set, or both are null.
        if (address(feedToken0) != address(0)) {
            // Feeds have been set, oracle deviation should be checked.
            // If feeds are not set, then HOT is in AMM-only mode, and oracle deviation check is not required.
            if (
                !HOTParams.checkPriceDeviation(
                    sqrtSpotPriceX96Cache,
                    getSqrtOraclePriceX96(),
                    hotReadSlotCache.maxOracleDeviationBipsLower,
                    hotReadSlotCache.maxOracleDeviationBipsUpper
                )
            ) {
                revert HOT__setPriceBounds_spotPriceAndOracleDeviation();
            }
        }

        // Check that new bounds are valid,
        // and do not exclude current spot price
        HOTParams.validatePriceBounds(sqrtSpotPriceX96Cache, _sqrtPriceLowX96, _sqrtPriceHighX96);

        // Update AMM sqrt spot price, sqrt price low and sqrt price high
        _ammState.setState(sqrtSpotPriceX96Cache, _sqrtPriceLowX96, _sqrtPriceHighX96);

        // Update AMM liquidity
        _updateAMMLiquidity(_calculateAMMLiquidity());

        emit PriceBoundSet(_sqrtPriceLowX96, _sqrtPriceHighX96);
    }

    /** 
        @notice Sets the AMM fee parameters directly.
        @param _feeMinToken0 Minimum fee for token0.
        @param _feeMaxToken0 Maximum fee for token0.
        @param _feeGrowthE6Token0 Fee growth rate for token0.
        @param _feeMinToken1 Minimum fee for token1.
        @param _feeMaxToken1 Maximum fee for token1.
        @param _feeGrowthE6Token1 Fee growth rate for token1.
        @dev Only callable by `liquidityProvider`. Can allow liquidity provider to override fees.
        @dev It is recommended that `liquidityProvider` implements a timelock when calling this function.
     */
    function setAMMFees(
        uint16 _feeMinToken0,
        uint16 _feeMaxToken0,
        uint16 _feeGrowthE6Token0,
        uint16 _feeMinToken1,
        uint16 _feeMaxToken1,
        uint16 _feeGrowthE6Token1
    ) public onlyUnpaused onlyLiquidityProvider {
        HOTParams.validateFeeParams(
            _feeMinToken0,
            _feeMaxToken0,
            _feeGrowthE6Token0,
            _feeMinToken1,
            _feeMaxToken1,
            _feeGrowthE6Token1,
            _minAMMFee,
            _minAMMFeeGrowthE6,
            _maxAMMFeeGrowthE6
        );

        HotWriteSlot memory hotWriteSlotCache = hotWriteSlot;

        hotWriteSlotCache.feeMinToken0 = _feeMinToken0;
        hotWriteSlotCache.feeMaxToken0 = _feeMaxToken0;
        hotWriteSlotCache.feeGrowthE6Token0 = _feeGrowthE6Token0;
        hotWriteSlotCache.feeMinToken1 = _feeMinToken1;
        hotWriteSlotCache.feeMaxToken1 = _feeMaxToken1;
        hotWriteSlotCache.feeGrowthE6Token1 = _feeGrowthE6Token1;

        hotWriteSlot = hotWriteSlotCache;

        emit AMMFeeSet(_feeMaxToken0, _feeMaxToken1);
    }

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

    /**
        @notice Sovereign ALM function to be called on every swap.
        @param _almLiquidityQuoteInput Contains fundamental information about the swap and `pool`.
        @param _externalContext Bytes encoded calldata, containing required off-chain data. 
        @return liquidityQuote Returns a quote to authorize `pool` to execute the swap.
     */
    function getLiquidityQuote(
        ALMLiquidityQuoteInput memory _almLiquidityQuoteInput,
        bytes calldata _externalContext,
        bytes calldata /*_verifierData*/
    ) external override onlyPool onlyUnpaused returns (ALMLiquidityQuote memory liquidityQuote) {
        if (_externalContext.length == 0) {
            // AMM Swap
            _ammSwap(_almLiquidityQuoteInput, liquidityQuote);
        } else {
            // Hot Swap
            _hotSwap(_almLiquidityQuoteInput, _externalContext, liquidityQuote);

            // Hot swap needs a swap callback, to update AMM liquidity correctly
            liquidityQuote.isCallbackOnSwap = true;
        }

        if (liquidityQuote.amountOut == 0) {
            revert HOT__getLiquidityQuote_zeroAmountOut();
        }
    }

    /**
        @notice Sovereign ALM function to deposit reserves into `pool`.
        @param _amount0 Amount of token0 to deposit.
        @param _amount1 Amount of token1 to deposit.
        @param _expectedSqrtSpotPriceLowerX96 Minimum expected sqrt spot price, to mitigate against its manipulation.
        @param _expectedSqrtSpotPriceUpperX96 Maximum expected sqrt spot price, to mitigate against its manipulation.
        @return amount0Deposited Amount of token0 deposited (it can differ from `_amount0` in case of rebase tokens).
        @return amount1Deposited Amount of token1 deposited (it can differ from `_amount1` in case of rebase tokens).
        @dev Only callable by `liquidityProvider`.
        @dev It assumes that `liquidityProvider` implements sufficient internal protection against
             sandwich attacks or other types of spot price manipulation attacks. 
     */
    function depositLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        uint160 _expectedSqrtSpotPriceLowerX96,
        uint160 _expectedSqrtSpotPriceUpperX96
    ) external onlyLiquidityProvider onlyUnpaused returns (uint256 amount0Deposited, uint256 amount1Deposited) {
        // Allow `liquidityProvider` to cross-check sqrt spot price against expected bounds,
        // to protect against its manipulation
        uint160 sqrtSpotPriceX96Cache = _checkSpotPriceRange(
            _expectedSqrtSpotPriceLowerX96,
            _expectedSqrtSpotPriceUpperX96
        );

        // It is sufficient to check only feedToken0, because either both of the feeds are set, or both are null.
        if (address(feedToken0) != address(0)) {
            // Feeds have been set, oracle deviation should be checked.
            // If feeds are not set, then HOT is in AMM-only mode, and oracle deviation check is not required.
            if (
                !HOTParams.checkPriceDeviation(
                    sqrtSpotPriceX96Cache,
                    getSqrtOraclePriceX96(),
                    hotReadSlot.maxOracleDeviationBipsLower,
                    hotReadSlot.maxOracleDeviationBipsUpper
                )
            ) {
                revert HOT__depositLiquidity_spotPriceAndOracleDeviation();
            }
        }

        // Deposit amount(s) into pool
        (amount0Deposited, amount1Deposited) = ISovereignPool(_pool).depositLiquidity(
            _amount0,
            _amount1,
            _liquidityProvider,
            '',
            ''
        );

        // Update AMM liquidity with post-deposit reserves
        _updateAMMLiquidity(_calculateAMMLiquidity());
    }

    /**
        @notice Sovereign ALM function to withdraw reserves from `pool`.
        @param _amount0 Amount of token0 to withdraw.
        @param _amount1 Amount of token1 to withdraw.
        @param _recipient Address of recipient.
        @param _expectedSqrtSpotPriceLowerX96 Minimum expected sqrt spot price, to mitigate against its manipulation.
        @param _expectedSqrtSpotPriceUpperX96 Maximum expected sqrt spot price, to mitigate against its manipulation.
        @dev Only callable by `liquidityProvider`.
        @dev It assumes that `liquidityProvider` implements sufficient internal protection against
             sandwich attacks or other types of spot price manipulation attacks. 
     */
    function withdrawLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        address _recipient,
        uint160 _expectedSqrtSpotPriceLowerX96,
        uint160 _expectedSqrtSpotPriceUpperX96
    ) external onlyLiquidityProvider {
        // Allow `liquidityProvider` to cross-check sqrt spot price against expected bounds,
        // to protect against its manipulation
        uint160 sqrtSpotPriceX96Cache = _checkSpotPriceRange(
            _expectedSqrtSpotPriceLowerX96,
            _expectedSqrtSpotPriceUpperX96
        );

        uint128 preWithdrawalLiquidity = _effectiveAMMLiquidity;

        ISovereignPool(_pool).withdrawLiquidity(_amount0, _amount1, _liquidityProvider, _recipient, '');

        // Update AMM liquidity with post-withdrawal reserves
        uint128 postWithdrawalLiquidity = _calculateAMMLiquidity();

        // Liquidity can never increase after a withdrawal, even if some passive reserves are added.
        if (postWithdrawalLiquidity < preWithdrawalLiquidity) {
            _updateAMMLiquidity(postWithdrawalLiquidity);
        } else {
            emit PostWithdrawalLiquidityCapped(sqrtSpotPriceX96Cache, preWithdrawalLiquidity, postWithdrawalLiquidity);
        }
    }

    /**
        @notice Swap Fee Module function to calculate swap fee multiplier, in basis-points (see docs).
        @param _tokenIn Address of token to swap from.
        @param _swapFeeModuleContext Bytes encoded calldata. Only needs to be non-empty for HOT swaps.
        @return swapFeeModuleData Struct containing `feeInBips` as the resulting swap fee.
     */
    function getSwapFeeInBips(
        address _tokenIn,
        address,
        uint256,
        address,
        bytes memory _swapFeeModuleContext
    ) external view returns (SwapFeeModuleData memory swapFeeModuleData) {
        bool isZeroToOne = (_token0 == _tokenIn);

        // Verification of branches is done during `getLiquidityQuote`
        if (_swapFeeModuleContext.length != 0) {
            // Hot Branch
            swapFeeModuleData.feeInBips = isZeroToOne ? hotReadSlot.hotFeeBipsToken0 : hotReadSlot.hotFeeBipsToken1;
        } else {
            // AMM Branch
            swapFeeModuleData.feeInBips = _getAMMFeeInBips(isZeroToOne);
        }
    }

    /**
        @notice Sovereign Pool callback on `depositLiquidity`.
        @dev This callback is used to transfer funds from `liquidityProvider` to `pool`.
        @dev Only callable by `pool`. 
     */
    function onDepositLiquidityCallback(
        uint256 _amount0,
        uint256 _amount1,
        bytes memory /*_data*/
    ) external override onlyPool {
        if (_amount0 > 0) {
            // Transfer token0 amount from `liquidityProvider` to `pool`
            address token0 = ISovereignPool(_pool).token0();
            IERC20(token0).safeTransferFrom(_liquidityProvider, msg.sender, _amount0);
        }

        if (_amount1 > 0) {
            // Transfer token1 amount from `_liquidityProvider` to `pool`
            address token1 = ISovereignPool(_pool).token1();
            IERC20(token1).safeTransferFrom(_liquidityProvider, msg.sender, _amount1);
        }
    }

    /**
        @notice Sovereign Pool callback on `swap`.
        @dev This is called at the end of each swap, to allow HOT to perform
             relevant state updates.
        @dev Only callable by `pool`.
     */
    function onSwapCallback(
        bool /*_isZeroToOne*/,
        uint256 /*_amountIn*/,
        uint256 /*_amountOut*/
    ) external override onlyPool {
        // Update AMM liquidity at the end of the swap
        _updateAMMLiquidity(_calculateAMMLiquidity());
    }

    /************************************************
     *  INTERNAL FUNCTIONS
     ***********************************************/

    /**
        @notice Helper function to calculate AMM dynamic swap fees.
     */
    function _getAMMFeeInBips(bool isZeroToOne) internal view returns (uint32 feeInBips) {
        HotWriteSlot memory hotWriteSlotCache = hotWriteSlot;

        // Determine min, max and growth rate (in pips per second),
        // depending on the requested input token
        uint16 feeMin = isZeroToOne ? hotWriteSlotCache.feeMinToken0 : hotWriteSlotCache.feeMinToken1;
        uint16 feeMax = isZeroToOne ? hotWriteSlotCache.feeMaxToken0 : hotWriteSlotCache.feeMaxToken1;
        uint16 feeGrowthE6 = isZeroToOne ? hotWriteSlotCache.feeGrowthE6Token0 : hotWriteSlotCache.feeGrowthE6Token1;

        // Calculate dynamic fee, linearly increasing over time
        uint256 feeInBipsTemp = uint256(feeMin) +
            Math.mulDiv(feeGrowthE6, (block.timestamp - hotWriteSlotCache.lastProcessedSignatureTimestamp), 100);

        // Cap fee to maximum value, if necessary
        if (feeInBipsTemp > feeMax) {
            feeInBipsTemp = feeMax;
        }

        feeInBips = uint32(feeInBipsTemp);
    }

    /**
        @notice Helper function to execute AMM swap. 
     */
    function _ammSwap(
        ALMLiquidityQuoteInput memory almLiquidityQuoteInput,
        ALMLiquidityQuote memory liquidityQuote
    ) internal {
        uint128 newLiquidity = _calculateAMMLiquidity();

        if (newLiquidity < _effectiveAMMLiquidity) {
            _updateAMMLiquidity(newLiquidity);
        }

        // Check that the fee path was chosen correctly
        if (almLiquidityQuoteInput.feeInBips != _getAMMFeeInBips(almLiquidityQuoteInput.isZeroToOne)) {
            revert HOT__getLiquidityQuote_invalidFeePath();
        }

        // Cache sqrt spot price, lower bound, and upper bound
        (uint160 sqrtSpotPriceX96Cache, uint160 sqrtPriceLowX96Cache, uint160 sqrtPriceHighX96Cache) = _getAMMState();

        // Calculate amountOut according to CPMM math
        uint160 sqrtSpotPriceX96New;
        (sqrtSpotPriceX96New, liquidityQuote.amountInFilled, liquidityQuote.amountOut, ) = SwapMath.computeSwapStep(
            sqrtSpotPriceX96Cache,
            almLiquidityQuoteInput.isZeroToOne ? sqrtPriceLowX96Cache : sqrtPriceHighX96Cache,
            _effectiveAMMLiquidity,
            almLiquidityQuoteInput.amountInMinusFee.toInt256(), // always exact input swap
            0 // fees have already been deducted
        );

        // New spot price cannot be at the edge of the price range, otherwise LiquidityAmounts library reverts.
        if (sqrtSpotPriceX96New == sqrtPriceLowX96Cache || sqrtSpotPriceX96New == sqrtPriceHighX96Cache) {
            revert HOT___ammSwap_invalidSpotPriceAfterSwap();
        }

        // Update AMM sqrt spot price
        _ammState.setSqrtSpotPriceX96(sqrtSpotPriceX96New);
    }

    /**
        @notice Helper function to execute HOT swap. 
     */
    function _hotSwap(
        ALMLiquidityQuoteInput memory almLiquidityQuoteInput,
        bytes memory externalContext,
        ALMLiquidityQuote memory liquidityQuote
    ) internal {
        (HybridOrderType memory hot, bytes memory signature) = abi.decode(externalContext, (HybridOrderType, bytes));

        // Execute HOT swap
        HotWriteSlot memory hotWriteSlotCache = hotWriteSlot;
        HotReadSlot memory hotReadSlotCache = hotReadSlot;

        // Check that the fee path was chosen correctly
        if (
            almLiquidityQuoteInput.feeInBips !=
            (almLiquidityQuoteInput.isZeroToOne ? hotReadSlotCache.hotFeeBipsToken0 : hotReadSlotCache.hotFeeBipsToken1)
        ) {
            revert HOT__getLiquidityQuote_invalidFeePath();
        }

        uint32 blockTimestamp = block.timestamp.toUint32();

        // An HOT only updates state if:
        // 1. It is the first HOT that updates state in the block.
        // 2. It was signed after the last processed signature timestamp.
        bool isDiscountedHot = blockTimestamp > hotWriteSlotCache.lastStateUpdateTimestamp &&
            hotWriteSlotCache.lastProcessedSignatureTimestamp < hot.signatureTimestamp;

        // Ensure that the number of HOT swaps per block does not exceed its maximum bound
        uint8 quotesInCurrentBlock = blockTimestamp > hotWriteSlotCache.lastProcessedQuoteTimestamp
            ? 1
            : hotWriteSlotCache.lastProcessedBlockQuoteCount + 1;

        if (quotesInCurrentBlock > hotReadSlotCache.maxAllowedQuotes) {
            revert HOT___hotSwap_maxHotQuotesExceeded();
        }

        // Pick the discounted or base price, depending on eligibility criteria set above
        // No need to check one against the other at this stage
        uint160 sqrtHotPriceX96 = isDiscountedHot ? hot.sqrtHotPriceX96Discounted : hot.sqrtHotPriceX96Base;

        // Calculate the amountOut according to the quoted price
        liquidityQuote.amountOut = almLiquidityQuoteInput.isZeroToOne
            ? (
                Math.mulDiv(
                    almLiquidityQuoteInput.amountInMinusFee * sqrtHotPriceX96,
                    sqrtHotPriceX96,
                    HOTConstants.Q192
                )
            )
            : (Math.mulDiv(almLiquidityQuoteInput.amountInMinusFee, HOTConstants.Q192, sqrtHotPriceX96) /
                sqrtHotPriceX96);

        // Fill tokenIn amount requested, excluding fees
        liquidityQuote.amountInFilled = almLiquidityQuoteInput.amountInMinusFee;

        // Check validity of new AMM dynamic fee parameters
        HOTParams.validateFeeParams(
            hot.feeMinToken0,
            hot.feeMaxToken0,
            hot.feeGrowthE6Token0,
            hot.feeMinToken1,
            hot.feeMaxToken1,
            hot.feeGrowthE6Token1,
            _minAMMFee,
            _minAMMFeeGrowthE6,
            _maxAMMFeeGrowthE6
        );

        hot.validateBasicParams(
            almLiquidityQuoteInput,
            liquidityQuote.amountOut,
            almLiquidityQuoteInput.isZeroToOne ? _maxToken1VolumeToQuote : _maxToken0VolumeToQuote,
            _maxDelay,
            hotWriteSlotCache.alternatingNonceBitmap
        );

        HOTParams.validatePriceConsistency(
            _ammState,
            sqrtHotPriceX96,
            hot.sqrtSpotPriceX96New,
            getSqrtOraclePriceX96(),
            hotReadSlot.maxOracleDeviationBipsLower,
            hotReadSlot.maxOracleDeviationBipsUpper,
            _hotMaxDiscountBipsLower,
            _hotMaxDiscountBipsUpper
        );

        // Verify HOT quote signature
        bytes32 hotHash = hot.hashParams();
        if (!hotReadSlotCache.signer.isValidSignatureNow(_hashTypedDataV4(hotHash), signature)) {
            revert HOT___hotSwap_invalidSignature();
        }

        // Only update the pool state, if this is a discounted hot quote
        if (isDiscountedHot) {
            // Update `hotWriteSlot`

            hotWriteSlotCache.feeGrowthE6Token0 = hot.feeGrowthE6Token0;
            hotWriteSlotCache.feeMaxToken0 = hot.feeMaxToken0;
            hotWriteSlotCache.feeMinToken0 = hot.feeMinToken0;
            hotWriteSlotCache.feeGrowthE6Token1 = hot.feeGrowthE6Token1;
            hotWriteSlotCache.feeMaxToken1 = hot.feeMaxToken1;
            hotWriteSlotCache.feeMinToken1 = hot.feeMinToken1;

            hotWriteSlotCache.lastProcessedSignatureTimestamp = hot.signatureTimestamp;
            hotWriteSlotCache.lastStateUpdateTimestamp = blockTimestamp;

            // Update AMM sqrt spot price
            _ammState.setSqrtSpotPriceX96(hot.sqrtSpotPriceX96New);
        }

        hotWriteSlotCache.lastProcessedBlockQuoteCount = quotesInCurrentBlock;
        hotWriteSlotCache.lastProcessedQuoteTimestamp = blockTimestamp;
        hotWriteSlotCache.alternatingNonceBitmap = hotWriteSlotCache.alternatingNonceBitmap.flipNonce(hot.nonce);

        // Update `hotWriteSlot`
        hotWriteSlot = hotWriteSlotCache;

        emit HotSwap(hotHash);
    }

    /************************************************
     *  PRIVATE FUNCTIONS
     ***********************************************/

    /**
        @notice Helper function to calculate AMM's effective liquidity. 
     */
    function _calculateAMMLiquidity() private view returns (uint128 updatedLiquidity) {
        (uint160 sqrtSpotPriceX96Cache, uint160 sqrtPriceLowX96Cache, uint160 sqrtPriceHighX96Cache) = _getAMMState();

        // Query current pool reserves
        (uint256 reserve0, uint256 reserve1) = ISovereignPool(_pool).getReserves();

        // Calculate liquidity corresponding to each of token's reserves and respective price ranges
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
            updatedLiquidity = liquidity0;
        } else {
            updatedLiquidity = liquidity1;
        }
    }

    /**
        @notice Helper function to update AMM's effective liquidity
     */
    function _updateAMMLiquidity(uint128 updatedLiquidity) internal {
        // Update effective AMM liquidity
        _effectiveAMMLiquidity = updatedLiquidity;
    }

    /**
        @notice Helper function to view AMM's prices
     */
    function _getAMMState()
        private
        view
        returns (uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96)
    {
        (sqrtSpotPriceX96, sqrtPriceLowX96, sqrtPriceHighX96) = _ammState.getState();
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
    ) private view returns (uint160 sqrtSpotPriceX96Cache) {
        sqrtSpotPriceX96Cache = _ammState.getSqrtSpotPriceX96();
        bool checkSqrtSpotPriceAbsDiff = _expectedSqrtSpotPriceUpperX96 != 0 || _expectedSqrtSpotPriceLowerX96 != 0;
        bool isZero = _expectedSqrtSpotPriceUpperX96 == 0 || _expectedSqrtSpotPriceLowerX96 == 0;

        if (checkSqrtSpotPriceAbsDiff && !isZero) {
            // Check that spot price has not been manipulated
            if (
                sqrtSpotPriceX96Cache > _expectedSqrtSpotPriceUpperX96 ||
                sqrtSpotPriceX96Cache < _expectedSqrtSpotPriceLowerX96
            ) {
                revert HOT___checkSpotPriceRange_invalidSqrtSpotPriceX96(sqrtSpotPriceX96Cache);
            }
        } else if (checkSqrtSpotPriceAbsDiff && isZero) {
            revert HOT___checkSpotPriceRange_invalidBounds();
        }
    }

    function _onlyPool() private view {
        if (msg.sender != _pool) {
            revert HOT__onlyPool();
        }
    }

    function _onlyManager() private view {
        if (msg.sender != manager) {
            revert HOT__onlyManager();
        }
    }

    function _onlyUnpaused() private view {
        if (hotReadSlot.isPaused) {
            revert HOT__onlyUnpaused();
        }
    }

    function _onlyLiquidityProvider() private view {
        if (msg.sender != _liquidityProvider) {
            revert HOT__onlyLiquidityProvider();
        }
    }

    function _poolNonReentrant() private view {
        if (ISovereignPool(_pool).isLocked()) {
            revert HOT__poolReentrant();
        }
    }
}
