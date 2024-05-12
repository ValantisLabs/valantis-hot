// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import 'forge-std/console.sol';

import {
    SovereignPool,
    SovereignPoolBase,
    SovereignPoolConstructorArgs
} from '../../lib/valantis-core/test/base/SovereignPoolBase.t.sol';
import { Base } from '../../lib/valantis-core/test/base/Base.sol';
import { SafeCast } from '../../lib/valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import { Math } from '../../lib/valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';

import { HOT } from '../../src/HOT.sol';
import { HOTConstants } from '../../src/libraries/HOTConstants.sol';
import {
    HOTConstructorArgs,
    HybridOrderType,
    HotWriteSlot,
    HotReadSlot,
    AMMState
} from '../../src/structs/HOTStructs.sol';
import { HOTOracle } from '../../src/HOTOracle.sol';
import { TightPack } from '../../src/libraries/utils/TightPack.sol';

import { HOTOracleHelper } from '../helpers/HOTOracleHelper.sol';
import { HOTDeployer } from '../deployers/HOTDeployer.sol';
import { MockChainlinkOracle } from '../mocks/MockChainlinkOracle.sol';
import { MockSigner } from '../mocks/MockSigner.sol';

contract HOTBase is SovereignPoolBase, HOTDeployer {
    using SafeCast for uint256;
    using TightPack for AMMState;

    struct PoolState {
        uint160 sqrtSpotPriceX96;
        uint160 sqrtPriceLowX96;
        uint160 sqrtPriceHighX96;
        uint256 reserve0;
        uint256 reserve1;
        uint256 managerFee0;
        uint256 managerFee1;
    }

    uint256 public EOASignerPrivateKey = 0x12345;
    address public EOASigner = vm.addr(EOASignerPrivateKey);

    HOT public hot;

    MockSigner public mockSigner;

    MockChainlinkOracle public feedToken0;
    MockChainlinkOracle public feedToken1;

    AMMState public mockAMMState;

    address public hotImmutablePool;
    address public hotImmutableLiquidityProvider;
    uint32 public hotImmutableMaxDelay;
    uint16 public hotImmutableHotMaxDiscountBipsLower;
    uint16 public hotImmutableHotMaxDiscountBipsUpper;
    uint16 public hotImmutableMaxOracleDeviationBound;
    uint16 public hotImmutableMinAMMFeeGrowthE6;
    uint16 public hotImmutableMaxAMMFeeGrowthE6;
    uint16 public hotImmutableMinAMMFee;

    function setUp() public virtual override {
        _setupBase();

        (feedToken0, feedToken1) = deployChainlinkOracles(8, 8);

        mockSigner = new MockSigner();

        // Set initial price to 2000 for token0 and 1 for token1 (Similar to Eth/USDC pair)
        feedToken0.updateAnswer(2000e8);
        feedToken1.updateAnswer(1e8);

        SovereignPoolConstructorArgs memory poolArgs = _generateDefaultConstructorArgs();
        pool = this.deploySovereignPool(poolArgs);
        hot = deployAndSetDefaultHOT(pool);

        _updateImmutables(hot);

        _addToContractsToApprove(address(pool));
        _addToContractsToApprove(address(hot));
    }

    function generateDefaultHOTConstructorArgs(
        SovereignPool _pool
    ) public view returns (HOTConstructorArgs memory args) {
        (uint16 hotDiscountDeviationLower, uint16 hotDiscountDeviationUpper) = getSqrtDeviationValues(200);

        args = HOTConstructorArgs({
            pool: address(_pool),
            manager: address(this),
            signer: address(mockSigner),
            liquidityProvider: address(this),
            feedToken0: address(feedToken0),
            feedToken1: address(feedToken1),
            sqrtSpotPriceX96: getSqrtPriceX96(2000 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
            sqrtPriceLowX96: getSqrtPriceX96(1500 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
            sqrtPriceHighX96: getSqrtPriceX96(2500 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
            maxDelay: 9 minutes,
            maxOracleUpdateDurationFeed0: 10 minutes,
            maxOracleUpdateDurationFeed1: 10 minutes,
            hotMaxDiscountBipsLower: hotDiscountDeviationLower, // Corresponds to 2%
            hotMaxDiscountBipsUpper: hotDiscountDeviationUpper, // Corresponds to 2%
            maxOracleDeviationBound: 5000, // 50%
            minAMMFeeGrowthE6: 100,
            maxAMMFeeGrowthE6: 10000,
            minAMMFee: 1 // 0.01%
        });
    }

    function deployAndSetDefaultHOT(SovereignPool _pool) public returns (HOT _hot) {
        HOTConstructorArgs memory args = generateDefaultHOTConstructorArgs(_pool);

        vm.startPrank(_pool.poolManager());
        _hot = this.deployHOT(args);
        _pool.setALM(address(_hot));
        _pool.setSwapFeeModule(address(_hot));
        vm.stopPrank();
    }

    function deployChainlinkOracles(
        uint8 feedToken0Decimals,
        uint8 feedToken1Decimals
    ) public returns (MockChainlinkOracle _feedToken0, MockChainlinkOracle _feedToken1) {
        _feedToken0 = new MockChainlinkOracle(feedToken0Decimals);
        _feedToken1 = new MockChainlinkOracle(feedToken1Decimals);

        return (_feedToken0, _feedToken1);
    }

    /// @dev This is only used for testing, during deployment HOTOracle is inherited by HOT
    function deployHOTOracleIndependently(
        MockChainlinkOracle _feedToken0,
        MockChainlinkOracle _feedToken1,
        uint32 _maxOracleUpdateDurationFeed0,
        uint32 _maxOracleUpdateDurationFeed1
    ) public returns (HOTOracle oracle) {
        oracle = new HOTOracle(
            address(pool.token0()),
            address(pool.token1()),
            address(_feedToken0),
            address(_feedToken1),
            _maxOracleUpdateDurationFeed0,
            _maxOracleUpdateDurationFeed1
        );
    }

    /// @dev This is only used for testing, during deployment HOTOracle is inherited by HOT
    function deployHOTOracleHelper(
        address _token0,
        address _token1,
        MockChainlinkOracle _feedToken0,
        MockChainlinkOracle _feedToken1,
        uint32 _maxOracleUpdateDurationFeed0,
        uint32 _maxOracleUpdateDurationFeed1
    ) public returns (HOTOracleHelper oracle) {
        oracle = new HOTOracleHelper(
            _token0,
            _token1,
            address(_feedToken0),
            address(_feedToken1),
            _maxOracleUpdateDurationFeed0,
            _maxOracleUpdateDurationFeed1
        );
    }

    function _updateImmutables(HOT _hot) internal {
        (
            address _hotImmutablePool,
            address _hotImmutableLiquidityProvider,
            uint32 _hotImmutableMaxDelay,
            uint16 _hotImmutableHotMaxDiscountBipsLower,
            uint16 _hotImmutableHotMaxDiscountBipsUpper,
            uint16 _hotImmutableMaxOracleDeviationBound,
            uint16 _hotImmutableMinAMMFeeGrowthE6,
            uint16 _hotImmutableMaxAMMFeeGrowthE6,
            uint16 _hotImmutableMinAMMFee
        ) = _hot.immutables();

        hotImmutablePool = _hotImmutablePool;
        hotImmutableLiquidityProvider = _hotImmutableLiquidityProvider;
        hotImmutableMaxDelay = _hotImmutableMaxDelay;
        hotImmutableHotMaxDiscountBipsLower = _hotImmutableHotMaxDiscountBipsLower;
        hotImmutableHotMaxDiscountBipsUpper = _hotImmutableHotMaxDiscountBipsUpper;
        hotImmutableMaxOracleDeviationBound = _hotImmutableMaxOracleDeviationBound;
        hotImmutableMinAMMFeeGrowthE6 = _hotImmutableMinAMMFeeGrowthE6;
        hotImmutableMaxAMMFeeGrowthE6 = _hotImmutableMaxAMMFeeGrowthE6;
        hotImmutableMinAMMFee = _hotImmutableMinAMMFee;
    }

    function _getSensibleHOTParams() internal returns (HybridOrderType memory hotParams) {
        // sqrt(2000) * 2^96 = 3543191142285914205922034323214
        // Sensible Defaults
        hotParams = HybridOrderType({
            amountInMax: 100e18,
            sqrtHotPriceX96Discounted: 3525430673841938976158389176523, // 1% discount to first HOT ( 1980 )
            sqrtHotPriceX96Base: 3543191142285914205922034323214, // 2000
            sqrtSpotPriceX96New: getSqrtPriceX96(
                2005 * (10 ** feedToken0.decimals()),
                1 * (10 ** feedToken1.decimals())
            ), // AMM spot price 2005
            authorizedSender: address(this),
            authorizedRecipient: makeAddr('RECIPIENT'),
            signatureTimestamp: (block.timestamp).toUint32(),
            expiry: 24, // 2 Blocks
            feeMinToken0: 10, // 0.1%
            feeMaxToken0: 100, // 1%
            feeGrowthE6Token0: 500, // 5 bips per second
            feeMinToken1: 10,
            feeMaxToken1: 100,
            feeGrowthE6Token1: 500,
            nonce: 1,
            expectedFlag: 0,
            isZeroToOne: true
        });
    }

    function getSqrtPriceX96(uint256 price0USD, uint256 price1USD) public view returns (uint160 sqrtOraclePriceX96) {
        uint256 oracle0Base = 10 ** feedToken0.decimals();
        uint256 oracle1Base = 10 ** feedToken1.decimals();
        uint256 token0Base = 10 ** token0.decimals();
        uint256 token1Base = 10 ** token1.decimals();

        uint256 oraclePriceX96 = Math.mulDiv(
            price0USD * oracle1Base * token1Base,
            1 << 96,
            price1USD * oracle0Base * token0Base
        );

        return (Math.sqrt(oraclePriceX96) << 48).toUint160();
    }

    function getDomainSeparatorV4(uint256 chainId, address hotAddress) public pure returns (bytes32 domainSeparator) {
        bytes32 typeHash = keccak256(
            'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
        );
        bytes32 hashedName = keccak256('Valantis HOT');
        bytes32 hashedVersion = keccak256('1');
        domainSeparator = keccak256(abi.encode(typeHash, hashedName, hashedVersion, chainId, hotAddress));
    }

    function getEOASignedQuote(
        HybridOrderType memory hotParams,
        uint256 privateKey
    ) public view returns (bytes memory signedQuoteExternalContext) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                getDomainSeparatorV4(block.chainid, address(hot)),
                keccak256(abi.encode(HOTConstants.HOT_TYPEHASH, hotParams))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, bytes1(v));

        signedQuoteExternalContext = abi.encode(hotParams, signature);
    }

    function getPoolState() public view returns (PoolState memory state) {
        (uint256 poolReserve0, uint256 poolReserve1) = pool.getReserves();
        (uint256 managerFee0, uint256 managerFee1) = pool.getPoolManagerFees();
        (uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96) = hot.getAMMState();

        state = PoolState({
            sqrtSpotPriceX96: sqrtSpotPriceX96,
            sqrtPriceLowX96: sqrtPriceLowX96,
            sqrtPriceHighX96: sqrtPriceHighX96,
            reserve0: poolReserve0,
            reserve1: poolReserve1,
            managerFee0: managerFee0,
            managerFee1: managerFee1
        });
    }

    function getHotReadSlot() public view returns (HotReadSlot memory slot) {
        (
            slot.isPaused,
            slot.maxAllowedQuotes,
            slot.maxOracleDeviationBipsLower,
            slot.maxOracleDeviationBipsUpper,
            slot.hotFeeBipsToken0,
            slot.hotFeeBipsToken1,
            slot.signer
        ) = hot.hotReadSlot();
    }

    function getHotWriteSlot() public view returns (HotWriteSlot memory slot) {
        // This pattern is used to prevent stack too deep errors
        (
            ,
            ,
            ,
            ,
            slot.feeGrowthE6Token1,
            slot.feeMaxToken1,
            slot.feeMinToken1,
            slot.lastStateUpdateTimestamp,
            slot.lastProcessedQuoteTimestamp,
            slot.lastProcessedSignatureTimestamp,
            slot.alternatingNonceBitmap
        ) = hot.hotWriteSlot();

        (
            slot.lastProcessedBlockQuoteCount,
            slot.feeGrowthE6Token0,
            slot.feeMaxToken0,
            slot.feeMinToken0,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = hot.hotWriteSlot();
    }

    function checkPoolState(PoolState memory actual, PoolState memory expected) public {
        assertEq(actual.reserve0, expected.reserve0, 'checkPoolState: reserve0');
        assertEq(actual.reserve1, expected.reserve1, 'checkPoolState: reserve1');
        assertEq(actual.sqrtSpotPriceX96, expected.sqrtSpotPriceX96, 'checkPoolState: spotPrice');
        assertEq(actual.sqrtPriceLowX96, expected.sqrtPriceLowX96, 'checkPoolState: priceLow');
        assertEq(actual.sqrtPriceHighX96, expected.sqrtPriceHighX96, 'checkPoolState: priceHigh');
        assertEq(actual.managerFee0, expected.managerFee0, 'checkPoolState: managerFee0');
        assertEq(actual.managerFee1, expected.managerFee1, 'checkPoolState: managerFee1');
    }

    function checkHotWriteSlot(HotWriteSlot memory actual, HotWriteSlot memory expected) public {
        assertEq(
            actual.lastProcessedBlockQuoteCount,
            expected.lastProcessedBlockQuoteCount,
            'checkHotWriteSlot: lastProcessedBlockQuoteCount'
        );
        assertEq(actual.feeGrowthE6Token0, expected.feeGrowthE6Token0, 'checkHotWriteSlot: feeGrowthE6Token0');
        assertEq(actual.feeMaxToken0, expected.feeMaxToken0, 'checkHotWriteSlot: feeMaxToken0');
        assertEq(actual.feeMinToken0, expected.feeMinToken0, 'checkHotWriteSlot: feeMinToken0');
        assertEq(actual.feeGrowthE6Token1, expected.feeGrowthE6Token1, 'checkHotWriteSlot: feeGrowthE6Token1');
        assertEq(actual.feeMaxToken1, expected.feeMaxToken1, 'checkHotWriteSlot: feeMaxToken1');
        assertEq(actual.feeMinToken1, expected.feeMinToken1, 'checkHotWriteSlot: feeMinToken1');
        assertEq(
            actual.lastStateUpdateTimestamp,
            expected.lastStateUpdateTimestamp,
            'checkHotWriteSlot: lastStateUpdateTimestamp'
        );
        assertEq(
            actual.lastProcessedQuoteTimestamp,
            expected.lastProcessedQuoteTimestamp,
            'checkHotWriteSlot: lastProcessedQuoteTimestamp'
        );
        assertEq(
            actual.lastProcessedSignatureTimestamp,
            expected.lastProcessedSignatureTimestamp,
            'checkHotWriteSlot: lastProcessedSignatureTimestamp'
        );
        assertEq(
            actual.alternatingNonceBitmap,
            expected.alternatingNonceBitmap,
            'checkHotWriteSlot: alternatingNonceBitmap'
        );
    }

    function _setAMMState(uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96) internal {
        mockAMMState.setState(sqrtSpotPriceX96, sqrtPriceLowX96, sqrtPriceHighX96);

        vm.store(address(hot), bytes32(uint256(5)), bytes32(uint256(mockAMMState.slot1)));
        vm.store(address(hot), bytes32(uint256(6)), bytes32(uint256(mockAMMState.slot2)));

        // Check that the amm state is setup correctly
        (uint160 _sqrtSpotPriceX96, uint160 _sqrtPriceLowX96, uint160 _sqrtPriceHighX96) = hot.getAMMState();

        assertEq(sqrtSpotPriceX96, _sqrtSpotPriceX96, 'sqrtSpotPriceX96New');
        assertEq(sqrtPriceLowX96, _sqrtPriceLowX96, 'sqrtPriceLowX96New');
        assertEq(sqrtPriceHighX96, _sqrtPriceHighX96, 'sqrtPriceHighX96New');
    }

    function _setHotWriteSlot(HotWriteSlot memory slot) internal {
        bytes memory encodedData = abi.encodePacked(
            slot.alternatingNonceBitmap,
            slot.lastProcessedSignatureTimestamp,
            slot.lastProcessedQuoteTimestamp,
            slot.lastStateUpdateTimestamp,
            slot.feeMinToken1,
            slot.feeMaxToken1,
            slot.feeGrowthE6Token1,
            slot.feeMinToken0,
            slot.feeMaxToken0,
            slot.feeGrowthE6Token0,
            slot.lastProcessedBlockQuoteCount
        );
        bytes32 data = bytes32(encodedData);
        vm.store(address(hot), bytes32(uint256(7)), data);
    }

    function _setHotReadSlot(HotReadSlot memory slot) internal {
        bytes memory encodedData = abi.encodePacked(
            bytes2(0),
            slot.signer,
            slot.hotFeeBipsToken1,
            slot.hotFeeBipsToken0,
            slot.maxOracleDeviationBipsUpper,
            slot.maxOracleDeviationBipsLower,
            slot.maxAllowedQuotes,
            slot.isPaused
        );

        bytes32 data = bytes32(encodedData);
        vm.store(address(hot), bytes32(uint256(8)), data);

        HotReadSlot memory updateSlot = getHotReadSlot();

        assertEq(slot.signer, updateSlot.signer, 'signer');
        assertEq(slot.hotFeeBipsToken1, updateSlot.hotFeeBipsToken1, 'hotFeeBipsToken1');
        assertEq(slot.hotFeeBipsToken0, updateSlot.hotFeeBipsToken0, 'hotFeeBipsToken0');
        assertEq(
            slot.maxOracleDeviationBipsLower,
            updateSlot.maxOracleDeviationBipsLower,
            'maxOracleDeviationBipsLower'
        );
        assertEq(
            slot.maxOracleDeviationBipsUpper,
            updateSlot.maxOracleDeviationBipsUpper,
            'maxOracleDeviationBipsUpper'
        );
        assertEq(slot.maxAllowedQuotes, updateSlot.maxAllowedQuotes, 'maxAllowedQuotes');
        assertEq(slot.isPaused, updateSlot.isPaused, 'isPaused');
    }

    function getSqrtDeviationValues(
        uint256 priceDeviationInBips
    ) public pure returns (uint16 maxOracleDeviationBipsLower, uint16 maxOracleDeviationBipsUpper) {
        maxOracleDeviationBipsLower = (1e4 - Math.sqrt((1e4 - priceDeviationInBips) * 1e4)).toUint16();
        maxOracleDeviationBipsUpper = (Math.sqrt((1e4 + priceDeviationInBips) * 1e4) - 1e4).toUint16();
    }
}
