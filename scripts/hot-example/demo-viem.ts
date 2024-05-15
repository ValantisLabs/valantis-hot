import { privateKeyToAccount } from 'viem/accounts';
import { gnosis } from 'viem/chains';
import { Address, createWalletClient, http, publicActions } from 'viem';
import { SignTypedDataReturnType } from 'viem';

async function swap() {
  const headers = {
    'Content-Type': 'application/json',
    'X-API-Key': `${process.env.API_KEY}`,
  };

  const account = privateKeyToAccount(`0x${process.env.PK}`);

  const requestParams = JSON.stringify({
    authorized_recipient: account.address, // address which receives token out
    authorized_sender: account.address, // should be same address which calls pool contract
    chain_id: 100, // 1 for mainnet, 100 for gnosis
    token_in: '0x6A023CCd1ff6F2045C3309768eAd9E68F978f6e1', // weth on gnosis
    token_out: '0xDDAfbb505ad214D7b80b1f830fcCc89B60fb7A83', // USDC on gnosis
    expected_gas_price: '0', // 1 gwei gas price
    volume_token_in: '100000000000000', // 0.0001 * 1e18 ether
    volume_token_out_min: '290000', // 0.29 * 1e6 USDC
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
