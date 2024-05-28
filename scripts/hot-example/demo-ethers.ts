import { AddressLike, Wallet, ethers } from 'ethers';

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

  const gnosis_provider = new ethers.JsonRpcProvider(`${process.env.GNOSIS_RPC}`);

  const account = new Wallet(`0x${process.env.PK}`, gnosis_provider);

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
    volume_token_in: AMOUNT_IN.toString(), // 0.0001 * 1e18 ether
    volume_token_out_min: AMOUNT_OUT.toString(), // 0.29 * 1e6 USDC
    request_expiry: Math.ceil(Date.now() / 1000) + 30, // Expiry in 30 seconds
    quote_expiry: Math.ceil(Date.now() / 1000) + 120, // Quote valid for 120 seconds
  });

  const requestOptions = {
    body: requestParams,
    method: 'POST',
    headers,
  };

  const response = await fetch('https://hot.valantis.xyz/solver/order', requestOptions);
  const data = await response.json();

  console.log(data);

  const quote = data as {
    pool_address: AddressLike;
    signed_payload: string;
  };

  if (!quote.signed_payload) {
    console.log('Could not get signed payload');
    return;
  }

  const tx = await account.sendTransaction({
    to: quote.pool_address,
    data: quote.signed_payload,
    gasLimit: 1_000_000n,
  });

  const receipt = await tx.wait();

  console.log(receipt?.hash);
}

swap();
