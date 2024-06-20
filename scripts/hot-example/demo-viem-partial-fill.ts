import { privateKeyToAccount } from 'viem/accounts';
import { arbitrum, gnosis, mainnet } from 'viem/chains';
import { Address, createWalletClient, encodeAbiParameters, http, parseAbiParameters, publicActions } from 'viem';
import { SignTypedDataReturnType, decodeAbiParameters } from 'viem';

import { fetchAmountOut } from './utils/price-api';

async function swapPartialFill() {
  const headers = {
    'Content-Type': 'application/json',
    'X-API-Key': `${process.env.API_KEY}`,
  };

  const account = privateKeyToAccount(`0x${process.env.PK}`);

  // 0.0001 * 1e18 ether
  const AMOUNT_IN = BigInt('100000000000000');
  // to keep price upto date with current price, so order doesn't revert
  const AMOUNT_OUT = await fetchAmountOut(AMOUNT_IN);

  const requestParams = JSON.stringify({
    authorized_recipient: account.address, // address which receives token out
    authorized_sender: account.address, // should be same address which calls pool contract
    chain_id: 42161, // 1 for mainnet, 100 for arbitrum
    token_in: '0x82af49447d8a07e3bd95bd0d56f35241523fbab1', // weth on arbitrum
    token_out: '0xaf88d065e77c8cc2239327c5edb3a432268e5831', // USDC on arbitrum
    expected_gas_price: '0', // 1 gwei gas price
    amount_in: AMOUNT_IN.toString(),
    amount_out_requested: AMOUNT_OUT.toString(),
    request_expiry: Math.ceil(Date.now() / 1000) + 30, // Expiry in 30 seconds
  });

  const requestOptions: RequestInit = {
    body: requestParams,
    method: 'POST',
    headers,
  };

  const response = await fetch('https://hot.valantis.xyz/solver/order', requestOptions);
  const data = await response.json();
  console.log(data);

  const quote = data as {
    pool_address: Address;
    signed_payload: SignTypedDataReturnType;
    volume_token_out: string;
    amount_out_min_payload_offset: number;
    amount_payload_offset: number;
    gas_price: number;
  };

  const walletClient = createWalletClient({
    name: 'Main',
    account,
    chain: arbitrum,
    transport: http(`${process.env.ARBITRUM_RPC}`),
  }).extend(publicActions);

  if (!quote.signed_payload) {
    console.log('Could not get signed payload');
    return;
  }

  // Human readable ABI params from SovereignPool::swap (pool_address)
  const swapAbiParams = parseAbiParameters(
    '(bool isSwapCallback, bool isZeroToOne, uint256 amountIn, uint256 amountOutMin, uint256 deadline, address recipient, address swapTokenOut, (bytes externalContext, bytes verifierContext, bytes swapCallbackContext, bytes swapFeeModuleContext))'
  );

  // Decode signed_payload
  const payloadSliced = `0x${quote.signed_payload.slice(10)}`;
  const decodedParams = decodeAbiParameters(swapAbiParams, payloadSliced as `0x{string}`)[0];

  // Recalculate amountIn and amountOutMin to execute a partially fillable HOT swap
  const amountInPartialFill = AMOUNT_IN / BigInt('2');
  const amountOutMinPartialFill = AMOUNT_OUT / BigInt('2');

  // Re-encode payload with amountInPartialFill and amountOutMinPartialFill
  const encodedParamsPartialFill = encodeAbiParameters(swapAbiParams, [
    [
      decodedParams[0],
      decodedParams[1],
      amountInPartialFill,
      amountOutMinPartialFill,
      decodedParams[4],
      decodedParams[5],
      decodedParams[6],
      decodedParams[7],
    ],
  ]);
  const payloadPartialFill = `0x${quote.signed_payload.slice(2, 10)}${encodedParamsPartialFill.slice(
    2
  )}` as `0x{string}`;

  console.log('payload partial fill: ', payloadPartialFill);

  const txHash = await walletClient.sendTransaction({
    account,
    chain: arbitrum,
    to: quote.pool_address,
    value: 0n,
    data: payloadPartialFill,
    gas: 1_000_000n,
  });

  console.log(txHash);
}

swapPartialFill();
