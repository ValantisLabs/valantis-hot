import { privateKeyToAccount } from 'viem/accounts';
import { gnosis } from 'viem/chains';
import { Address, createWalletClient, http, publicActions } from 'viem';
import { SignTypedDataReturnType } from 'viem';

async function fetchAmountOut(amountIn: bigint): Promise<bigint> {
  const response = await fetch('https://api.binance.com/api/v3/ticker/price?symbol=ETHUSDC');
  const priceResult = (await response.json()) as {
    symbol: string;
    price: string;
  };

  return (BigInt(priceResult.price.split('.')[0]) * amountIn) / BigInt(10) ** BigInt(12);
}

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
    chain_id: 100, // 1 for mainnet, 100 for gnosis
    token_in: '0x6A023CCd1ff6F2045C3309768eAd9E68F978f6e1', // weth on gnosis (0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 for mainnet)
    token_out: '0xDDAfbb505ad214D7b80b1f830fcCc89B60fb7A83', // USDC on gnosis (0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48 for mainnet)
    expected_gas_price: '0', // 1 gwei gas price
    volume_token_in: AMOUNT_IN.toString(),
    volume_token_out_min: AMOUNT_OUT.toString(),
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
    chain: gnosis, // set to `mainnet` for mainnet
    transport: http(`${process.env.GNOSIS_RPC}`), //Set to MAINNET_RPC for mainnet
  }).extend(publicActions);

  if (!quote.signed_payload) {
    console.log('Could not get signed payload');
    return;
  }

  const txHash = await walletClient.sendTransaction({
    account,
    chain: gnosis,
    to: quote.pool_address,
    value: 0n,
    data: quote.signed_payload,
    gas: 1_000_000n,
  });

  console.log(txHash);
}

swap();
