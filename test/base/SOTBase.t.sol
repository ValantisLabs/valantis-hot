// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import 'forge-std/console.sol';
import {
    SovereignPool,
    SovereignPoolBase,
    SovereignPoolConstructorArgs
} from 'valantis-core/test/base/SovereignPoolBase.t.sol';
import { Base } from 'valantis-core/test/base/Base.sol';
import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';

import { SOT } from 'src/SOT.sol';
import { SOTConstants } from 'src/libraries/SOTConstants.sol';
import {
    SOTConstructorArgs,
    SolverOrderType,
    SolverWriteSlot,
    SolverReadSlot,
    AMMState
} from 'src/structs/SOTStructs.sol';
import { SOTOracle } from 'src/SOTOracle.sol';
import { TightPack } from 'src/libraries/utils/TightPack.sol';

import { SOTOracleHelper } from 'test/helpers/SOTOracleHelper.sol';
import { SOTDeployer } from 'test/deployers/SOTDeployer.sol';
import { MockChainlinkOracle } from 'test/mocks/MockChainlinkOracle.sol';
import { MockSigner } from 'test/mocks/MockSigner.sol';

contract SOTBase is SovereignPoolBase, SOTDeployer {
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

    SOT public sot;

    MockSigner public mockSigner;

    MockChainlinkOracle public feedToken0;
    MockChainlinkOracle public feedToken1;

    AMMState public mockAMMState;

    function setUp() public virtual override {
        _setupBase();

        (feedToken0, feedToken1) = deployChainlinkOracles(8, 8);

        mockSigner = new MockSigner();

        // Set initial price to 2000 for token0 and 1 for token1 (Similar to Eth/USDC pair)
        feedToken0.updateAnswer(2000e8);
        feedToken1.updateAnswer(1e8);

        SovereignPoolConstructorArgs memory poolArgs = _generateDefaultConstructorArgs();
        pool = this.deploySovereignPool(poolArgs);
        sot = deployAndSetDefaultSOT(pool);

        _addToContractsToApprove(address(pool));
        _addToContractsToApprove(address(sot));
    }

    function deployAndSetDefaultSOT(SovereignPool _pool) public returns (SOT _sot) {
        SOTConstructorArgs memory args = SOTConstructorArgs({
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
            solverMaxDiscountBips: 200, // 2%
            oraclePriceMaxDiffBips: 5000, // 50%
            minAMMFeeGrowthInPips: 100,
            maxAMMFeeGrowthInPips: 10000,
            minAMMFee: 1 // 0.01%
        });

        vm.startPrank(_pool.poolManager());
        _sot = this.deploySOT(args);
        _pool.setALM(address(_sot));
        _pool.setSwapFeeModule(address(_sot));
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

    /// @dev This is only used for testing, during deployment SOTOracle is inherited by SOT
    function deploySOTOracleIndependently(
        MockChainlinkOracle _feedToken0,
        MockChainlinkOracle _feedToken1,
        uint32 _maxOracleUpdateDurationFeed0,
        uint32 _maxOracleUpdateDurationFeed1
    ) public returns (SOTOracle oracle) {
        oracle = new SOTOracle(
            address(pool.token0()),
            address(pool.token1()),
            address(_feedToken0),
            address(_feedToken1),
            _maxOracleUpdateDurationFeed0,
            _maxOracleUpdateDurationFeed1
        );
    }

    /// @dev This is only used for testing, during deployment SOTOracle is inherited by SOT
    function deploySOTOracleHelper(
        address _token0,
        address _token1,
        MockChainlinkOracle _feedToken0,
        MockChainlinkOracle _feedToken1,
        uint32 _maxOracleUpdateDurationFeed0,
        uint32 _maxOracleUpdateDurationFeed1
    ) public returns (SOTOracleHelper oracle) {
        oracle = new SOTOracleHelper(
            _token0,
            _token1,
            address(_feedToken0),
            address(_feedToken1),
            _maxOracleUpdateDurationFeed0,
            _maxOracleUpdateDurationFeed1
        );
    }

    function _getSensibleSOTParams() internal returns (SolverOrderType memory sotParams) {
        // Sensible Defaults
        sotParams = SolverOrderType({
            amountInMax: 100e18,
            solverPriceX192Discounted: 1980 << 192, // 1% discount to first solver
            solverPriceX192Base: 2000 << 192,
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
            feeGrowthInPipsToken0: 500, // 5 bips per second
            feeMinToken1: 10,
            feeMaxToken1: 100,
            feeGrowthInPipsToken1: 500,
            nonce: 1,
            expectedFlag: 0
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

    function getEOASignedQuote(
        SolverOrderType memory sotParams,
        uint256 privateKey
    ) public view returns (bytes memory signedQuoteExternalContext) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                sot.domainSeparatorV4(),
                keccak256(abi.encode(SOTConstants.SOT_TYPEHASH, sotParams))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, bytes1(v));

        signedQuoteExternalContext = abi.encode(sotParams, signature);
    }

    function getPoolState() public view returns (PoolState memory state) {
        (uint256 poolReserve0, uint256 poolReserve1) = pool.getReserves();
        (uint256 managerFee0, uint256 managerFee1) = pool.getPoolManagerFees();
        (uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96) = sot.getAMMState();

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

    function getSolverReadSlot() public view returns (SolverReadSlot memory slot) {
        (slot.maxAllowedQuotes, slot.solverFeeBipsToken0, slot.solverFeeBipsToken1, slot.signer) = sot.solverReadSlot();
    }

    function getSolverWriteSlot() public view returns (SolverWriteSlot memory slot) {
        // This pattern is used to prevent stack too deep errors
        (
            ,
            ,
            ,
            ,
            slot.feeGrowthInPipsToken1,
            slot.feeMaxToken1,
            slot.feeMinToken1,
            slot.lastStateUpdateTimestamp,
            slot.lastProcessedQuoteTimestamp,
            slot.lastProcessedSignatureTimestamp,
            slot.alternatingNonceBitmap
        ) = sot.solverWriteSlot();

        (
            slot.lastProcessedBlockQuoteCount,
            slot.feeGrowthInPipsToken0,
            slot.feeMaxToken0,
            slot.feeMinToken0,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = sot.solverWriteSlot();
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

    function checkSolverWriteSlot(SolverWriteSlot memory actual, SolverWriteSlot memory expected) public {
        assertEq(
            actual.lastProcessedBlockQuoteCount,
            expected.lastProcessedBlockQuoteCount,
            'checkSolverWriteSlot: lastProcessedBlockQuoteCount'
        );
        assertEq(
            actual.feeGrowthInPipsToken0,
            expected.feeGrowthInPipsToken0,
            'checkSolverWriteSlot: feeGrowthInPipsToken0'
        );
        assertEq(actual.feeMaxToken0, expected.feeMaxToken0, 'checkSolverWriteSlot: feeMaxToken0');
        assertEq(actual.feeMinToken0, expected.feeMinToken0, 'checkSolverWriteSlot: feeMinToken0');
        assertEq(
            actual.feeGrowthInPipsToken1,
            expected.feeGrowthInPipsToken1,
            'checkSolverWriteSlot: feeGrowthInPipsToken1'
        );
        assertEq(actual.feeMaxToken1, expected.feeMaxToken1, 'checkSolverWriteSlot: feeMaxToken1');
        assertEq(actual.feeMinToken1, expected.feeMinToken1, 'checkSolverWriteSlot: feeMinToken1');
        assertEq(
            actual.lastStateUpdateTimestamp,
            expected.lastStateUpdateTimestamp,
            'checkSolverWriteSlot: lastStateUpdateTimestamp'
        );
        assertEq(
            actual.lastProcessedQuoteTimestamp,
            expected.lastProcessedQuoteTimestamp,
            'checkSolverWriteSlot: lastProcessedQuoteTimestamp'
        );
        assertEq(
            actual.lastProcessedSignatureTimestamp,
            expected.lastProcessedSignatureTimestamp,
            'checkSolverWriteSlot: lastProcessedSignatureTimestamp'
        );
        assertEq(
            actual.alternatingNonceBitmap,
            expected.alternatingNonceBitmap,
            'checkSolverWriteSlot: alternatingNonceBitmap'
        );
    }

    function _setAMMState(uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96) internal {
        mockAMMState.setState(sqrtSpotPriceX96, sqrtPriceLowX96, sqrtPriceHighX96);

        vm.store(address(sot), bytes32(uint256(2)), bytes32(uint256(mockAMMState.slot1)));
        vm.store(address(sot), bytes32(uint256(3)), bytes32(uint256(mockAMMState.slot2)));

        // Check that the amm state is setup correctly
        (uint160 _sqrtSpotPriceX96, uint160 _sqrtPriceLowX96, uint160 _sqrtPriceHighX96) = sot.getAMMState();

        assertEq(sqrtSpotPriceX96, _sqrtSpotPriceX96, 'sqrtSpotPriceX96New');
        assertEq(sqrtPriceLowX96, _sqrtPriceLowX96, 'sqrtPriceLowX96New');
        assertEq(sqrtPriceHighX96, _sqrtPriceHighX96, 'sqrtPriceHighX96New');
    }

    function _setSolverWriteSlot(SolverWriteSlot memory slot) internal {
        bytes memory encodedData = abi.encodePacked(
            slot.alternatingNonceBitmap,
            slot.lastProcessedSignatureTimestamp,
            slot.lastProcessedQuoteTimestamp,
            slot.lastStateUpdateTimestamp,
            slot.feeMinToken1,
            slot.feeMaxToken1,
            slot.feeGrowthInPipsToken1,
            slot.feeMinToken0,
            slot.feeMaxToken0,
            slot.feeGrowthInPipsToken0,
            slot.lastProcessedBlockQuoteCount
        );
        bytes32 data = bytes32(encodedData);
        vm.store(address(sot), bytes32(uint256(5)), data);
    }

    function _setSolverReadSlot(SolverReadSlot memory slot) internal {
        bytes memory encodedData = abi.encodePacked(
            bytes7(0),
            slot.signer,
            slot.solverFeeBipsToken1,
            slot.solverFeeBipsToken0,
            slot.maxAllowedQuotes
        );
        bytes32 data = bytes32(encodedData);
        vm.store(address(sot), bytes32(uint256(6)), data);
    }
}
