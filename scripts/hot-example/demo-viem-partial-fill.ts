import { privateKeyToAccount } from 'viem/accounts';
import { gnosis } from 'viem/chains';
import { Address, createWalletClient, encodeAbiParameters, http, parseAbiParameters, publicActions } from 'viem';
import { SignTypedDataReturnType, decodeAbiParameters } from 'viem';

async function fetchAmountOut(amountIn: bigint): Promise<bigint> {
  const response = await fetch('https://api.binance.com/api/v3/ticker/price?symbol=ETHUSDC');
  const priceResult = (await response.json()) as {
    symbol: string;
    price: string;
  };

  return (BigInt(priceResult.price.split('.')[0]) * amountIn) / BigInt(10) ** BigInt(12);
}

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
    chain_id: 100, // 1 for mainnet, 100 for gnosis
    token_in: '0x6A023CCd1ff6F2045C3309768eAd9E68F978f6e1', // weth on gnosis
    token_out: '0xDDAfbb505ad214D7b80b1f830fcCc89B60fb7A83', // USDC on gnosis
    expected_gas_price: '0', // 1 gwei gas price
    volume_token_in: AMOUNT_IN.toString(),
    volume_token_out_min: AMOUNT_OUT.toString(),
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
  };

  const walletClient = createWalletClient({
    name: 'Main',
    account,
    chain: gnosis,
    transport: http(`${process.env.GNOSIS_RPC}`),
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

  const txHash = await walletClient.sendTransaction({
    account,
    chain: gnosis,
    to: quote.pool_address,
    value: 0n,
    data: payloadPartialFill,
    gas: 1_000_000n,
  });

  console.log(txHash);
}

swapPartialFill();
