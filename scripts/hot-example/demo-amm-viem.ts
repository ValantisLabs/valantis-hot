import { privateKeyToAccount } from 'viem/accounts';
import { arbitrum } from 'viem/chains';
import { createWalletClient, http, publicActions, parseAbi } from 'viem';

async function swap() {
  const account = privateKeyToAccount(`0x${process.env.PK}`);

  // This example works on Arbitrum
  // See deployments folder for other supported chains
  const chain = arbitrum;
  const rpcUrl = process.env.ARBITRUM_RPC;

  // 0.0001 * 1e18 ether
  const amountIn = BigInt('100000000000000');

  // WARNING: only use for mock testing
  const amountOutMin = BigInt('0');

  // WETH on Arbitrum
  const tokenIn = '0x82af49447d8a07e3bd95bd0d56f35241523fbab1';

  // USDC on Arbitrum
  const tokenOut = '0xaf88d065e77c8cc2239327c5edb3a432268e5831';

  // WETH/USDC Sovereign Pool on Arbitrum (the entry point for HOT AMM swaps)
  // See deployments folder for latest deployment addresses
  const sovereignPool = '0x6d0ed01ef1d3200d0ce47e969e939be78e5defc1';

  const walletClient = createWalletClient({
    name: 'Main',
    account,
    chain,
    transport: http(rpcUrl),
  }).extend(publicActions);

  // Human readable ABI params from SovereignPool::swap (pool_address)
  const swapAbiParams = parseAbi([
    'function swap((bool isSwapCallback, bool isZeroToOne, uint256 amountIn, uint256 amountOutMin, uint256 deadline, address recipient, address swapTokenOut, (bytes externalContext, bytes verifierContext, bytes swapCallbackContext, bytes swapFeeModuleContext)))',
  ]);

  const blockTimestamp = (await walletClient.getBlock()).timestamp;

  // IMPORTANT: This will only work of account.address has approved sovereignPool to transfer WETH

  const txHash = await walletClient.writeContract({
    address: sovereignPool,
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
