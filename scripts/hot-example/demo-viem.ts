import { privateKeyToAccount } from 'viem/accounts';
import { gnosis, arbitrum } from 'viem/chains';
import { Address, createWalletClient, http, publicActions } from 'viem';
import { SignTypedDataReturnType } from 'viem';

import { fetchAmountOut } from './utils/price-api';

async function swap() {
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
    chain_id: 42161, // 1 for mainnet, 42161 for arbitrum
    token_in: '0x82af49447d8a07e3bd95bd0d56f35241523fbab1', // weth on arbitrum (0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 for mainnet)
    token_out: '0xaf88d065e77c8cc2239327c5edb3a432268e5831', // USDC on arbitrum (0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48 for mainnet)
    expected_gas_price: '0',
    expected_gas_units: '0',
    amount_in: AMOUNT_IN.toString(),
    amount_out_requested: '0',
    request_expiry: Math.ceil(Date.now() / 1000) + 30, // Expiry in 30 seconds,
    quote_expiry: Math.ceil(Date.now() / 1000) + 120, // Quote valid for 120 seconds
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
  };

  const walletClient = createWalletClient({
    name: 'Main',
    account,
    chain: arbitrum, // set to `mainnet` for mainnet
    transport: http(`${process.env.ARBITRUM_RPC}`), //Set to MAINNET_RPC for mainnet
  }).extend(publicActions);

  if (!quote.signed_payload) {
    console.log('Could not get signed payload');
    return;
  }

  const txHash = await walletClient.sendTransaction({
    account,
    chain: arbitrum,
    to: quote.pool_address,
    value: 0n,
    data: quote.signed_payload,
    gas: 1_000_000n,
  });

  console.log(txHash);
}

swap();
