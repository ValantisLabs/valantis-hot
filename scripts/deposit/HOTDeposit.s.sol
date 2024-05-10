// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Script } from 'forge-std/Script.sol';
import { console } from 'forge-std/console.sol';

import { IArrakisMetaVault } from './interfaces/IArrakisMetaVault.sol';
import { IArrakisMetaVaultPublic } from './interfaces/IArrakisMetaVaultPublic.sol';
import { IArrakisPublicVaultRouter } from './interfaces/IArrakisPublicVaultRouter.sol';

import { ERC20 } from 'valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';

uint256 constant maxAmount1 = 152 * 10 ** 6;
uint256 constant maxAmount0 = 177561115760341835;

contract HOTDepositScript is Script {
    function run() public {
        string memory path = DeployHelper.getPath();
        string memory json = vm.readFile(path);

        uint256 depositorPrivateKey = vm.envUint('DEPOSITOR_PRIVATE_KEY');
        address account = vm.addr(depositorPrivateKey);

        address vault = vm.parseJsonAddress(json, '.ArrakisVault');
        address router = vm.parseJsonAddress(json, '.ArrakisRouter');

        vm.startBroadcast(depositorPrivateKey);

        (uint256 shares, uint256 amount0, uint256 amount1) = IArrakisPublicVaultRouter(router).getMintAmounts(
            vault,
            maxAmount0,
            maxAmount1
        );

        address token0 = IArrakisMetaVault(vault).token0();
        address token1 = IArrakisMetaVault(vault).token1();
        address module = address(IArrakisMetaVault(vault).module());

        ERC20(token0).approve(module, amount0);
        ERC20(token1).approve(module, amount1);

        IArrakisMetaVaultPublic(vault).mint(shares, account);

        console.logString('Valantis Public Vault mint');
        console.logAddress(vault);

        console.logUint(amount0);
        console.logUint(amount1);
        console.logUint(shares);

        vm.stopBroadcast();
    }
}
