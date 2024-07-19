import { privateKeyToAccount } from 'viem/accounts';
import { arbitrum } from 'viem/chains';
import { createWalletClient, http, publicActions, parseAbi } from 'viem';

async function swap() {
  const account = privateKeyToAccount(`0x${process.env.PK}`);

  // 0.0001 * 1e18 ether
  const amountIn = BigInt('100000000000000');

  // WARNING: only use for mock testing
  const amountOutMin = BigInt('0');

  // WETH on Arbitrum
  const tokenIn = '0x82af49447d8a07e3bd95bd0d56f35241523fbab1';

  // USDC on Arbitrum
  const tokenOut = '0xaf88d065e77c8cc2239327c5edb3a432268e5831';

  const walletClient = createWalletClient({
    name: 'Main',
    account,
    chain: arbitrum, // set to `mainnet` for mainnet
    transport: http(`${process.env.ARBITRUM_RPC}`), //Set to MAINNET_RPC for mainnet
  }).extend(publicActions);

  // Human readable ABI params from SovereignPool::swap (pool_address)
  const swapAbiParams = parseAbi([
    'function swap((bool isSwapCallback, bool isZeroToOne, uint256 amountIn, uint256 amountOutMin, uint256 deadline, address recipient, address swapTokenOut, (bytes externalContext, bytes verifierContext, bytes swapCallbackContext, bytes swapFeeModuleContext)))',
  ]);

  const blockTimestamp = (await walletClient.getBlock()).timestamp;

  const txHash = await walletClient.writeContract({
    address: '0x6d0ed01ef1d3200d0ce47e969e939be78e5defc1',
    abi: swapAbiParams,
    functionName: 'swap',
    args: [
      [
        false,
        true,
        amountIn,
        amountOutMin,
        blockTimestamp + 100n,
        account.address,
        tokenOut,
        { externalContext: '0x', verifierContext: '0x', swapCallbackContext: '0x', swapFeeModuleContext: '0x' },
      ],
    ],
    account,
  });

  console.log(txHash);
}

swap();
