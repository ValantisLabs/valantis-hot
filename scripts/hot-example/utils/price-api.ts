export async function fetchAmountOut(amountIn: bigint): Promise<bigint> {
  const response = await fetch('https://api.binance.com/api/v3/ticker/price?symbol=ETHUSDC');
  const priceResult = (await response.json()) as {
    symbol: string;
    price: string;
  };

  return (BigInt(priceResult.price.split('.')[0]) * amountIn) / BigInt(10) ** BigInt(12);
}
