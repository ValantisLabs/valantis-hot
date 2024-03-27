// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Script.sol';

import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

import { SOT } from 'src/SOT.sol';
import { MockLiquidityProvider } from 'test/mocks/MockLiquidityProvider.sol';
import { SOTConstructorArgs, SolverOrderType } from 'src/structs/SOTStructs.sol';
import { SOTBase } from 'test/base/SOTBase.t.sol';
import { SOTConstants } from 'src/libraries/SOTConstants.sol';

import {
    SovereignPool,
    SovereignPoolBase,
    SovereignPoolConstructorArgs,
    SovereignPoolSwapParams,
    SovereignPoolSwapContextData
} from 'valantis-core/test/base/SovereignPoolBase.t.sol';

import { MockToken } from 'test/mocks/MockToken.sol';
import { MockChainlinkOracle } from 'test/mocks/MockChainlinkOracle.sol';
import { SOTDeployer } from 'test/deployers/SOTDeployer.sol';
import { SovereignPoolDeployer } from 'valantis-core/test/deployers/SovereignPoolDeployer.sol';

import { AggregatorV3Interface } from 'src/vendor/chainlink/AggregatorV3Interface.sol';
import { IArrakisMetaVaultPublic } from 'src/vendor/arrakis/IArrakisMetaVaultPublic.sol';

contract OracleUpdateScript is Script {
    using SafeCast for uint256;

    function getSqrtPriceX96(
        MockToken token0,
        MockToken token1,
        MockChainlinkOracle feedToken0,
        MockChainlinkOracle feedToken1,
        uint256 price0USD,
        uint256 price1USD
    ) public view returns (uint160 sqrtOraclePriceX96) {
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

    function run() external {
        vm.startBroadcast(vm.envUint('SEPOLIA_PRIVATE_KEY'));

        SOT sot = SOT(vm.envAddress('SEPOLIA_SOT_MOCKS'));
        MockToken mockToken0 = MockToken(vm.envAddress('SEPOLIA_TOKEN0_MOCK'));
        MockToken mockToken1 = MockToken(vm.envAddress('SEPOLIA_TOKEN1_MOCK'));
        address sepoliaPublicKey = vm.envAddress('SEPOLIA_PUBLIC_KEY');

        // Note: Update these to relevant values, before making an SOT Swap. Not needed for AMM swap.
        (uint160 sqrtSpotPriceX96, , ) = sot.getAMMState();
        // uint256 spotPrice = Math.mulDiv(sqrtSpotPriceX96, sqrtSpotPriceX96, 1 << 192);

        MockChainlinkOracle feedToken0 = MockChainlinkOracle(vm.envAddress('SEPOLIA_ETH_USD_FEED_MOCKS'));
        MockChainlinkOracle feedToken1 = MockChainlinkOracle(vm.envAddress('SEPOLIA_USDC_USD_FEED_MOCKS'));
        uint256 spotPrice = 2300;

        feedToken0.updateAnswer((spotPrice * 1e20).toInt256());
        feedToken1.updateAnswer(1e8);

        (, int256 oraclePriceUSDInt0, , , ) = feedToken0.latestRoundData();
        (, int256 oraclePriceUSDInt1, , , ) = feedToken1.latestRoundData();

        console.logInt(oraclePriceUSDInt0);
        console.logInt(oraclePriceUSDInt1);
        console.log('AMM sqrt spot price X96:', sqrtSpotPriceX96);
        console.log('AMM max oracle deviation:', sot.maxOracleDeviationBips());
        console.log('AMM sqrt oracle price:', sot.getSqrtOraclePriceX96());

        // mockToken0.mint(address(sepoliaPublicKey), 1e40);
        // mockToken1.mint(address(sepoliaPublicKey), 1e40);

        IArrakisMetaVaultPublic metaVault = IArrakisMetaVaultPublic(vm.envAddress('SEPOLIA_ARRAKIS_META_VAULT_MOCKS'));

        MockLiquidityProvider liquidityProvider = MockLiquidityProvider(
            vm.envAddress('SEPOLIA_ARRAKIS_VALANTIS_MODULE_MOCKS')
        );

        // mockToken0.approve(address(liquidityProvider), 1e40);
        // mockToken1.approve(address(liquidityProvider), 1e40);

        // metaVault.mint(1e16, address(sepoliaPublicKey));

        // sot.setMaxOracleDeviationBips(50);

        vm.stopBroadcast();
    }
}
