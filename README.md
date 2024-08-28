![Valantis](img/Valantis_Banner.png)

# Valantis

Implementation of the Valantis HOT smart contracts in Solidity.

## Setting up Foundry

We use Foundry as our Solidity development framework. See [here](https://book.getfoundry.sh/getting-started/installation) for installation instructions, docs and examples.

Once installed, build the project:

```
forge build
```

Install dependencies:

```
forge install && yarn install
```

Tests:

To run foundry tests which included concrete tests and fuzz tests:

```
forge test
```

Deployments:

Smart contract deployments are done using forge script. These are tagged in `package.json` as `deploy:*`.

Simulate deployment without broadcasting:

```
yarn deploy:ProtocolFactory
```

Execute deployment and verify:

```
yarn deploy:ProtocolFactory --broadcast --verify
```

### Important:

Make sure that `RPC_URL` is set in `.env`, and any initialization values required by forge script are set in `/deployments/{chainId}.json` file.

Docs:

```
forge doc --serve --port 8080
```

## Folder structure description

### lib:

Contains all smart contract external dependencies, installed via Foundry as git submodules.
There are 4 dependencies to build HOT smart contracts -

- forge-std
- valantis-core
- v3-core
- v3-periphery

### src

All relevant contracts to be audited are in src folder (excluding `/mocks` folders). Number of lines of code:

```
cloc src --not-match-d=mocks
```

**HOT:** The main HOT smart contract logic, which implements `ISovereignALM` and `ISwapFeeModule` from `valantis-core`. HOT also inherits the HOTOracle logic. HOT holds the logic to calculate the liquidity algorithm

**HOTOracle:** Logic to retrieve latest price from chainlink feeds, and convert it into sqrtPriceX96.

**libraries:** Various helper libraries used in other contracts.

- TightPack: Low level library to pack 3 uint160 variables, into 2 storage slots at the byte level.
- AlternatingNonceBitmap: Implements a nonce data structure, to allow for cheap replay protection.
- HOTConstants: Internal library to store all the constant values for HOT and HOTOracle.
- HOTParams: Helper library to verify the correctness of the HOT values.

**vendor:** Interfaces for external smart contract dependencies i.e ArrakisMetaVault and Chainlink AggregatorV3 feeds.

### test

All relevent tests for contracts in src are in this folder

**base:** Base contracts for a respective contract, which are extended in concrete/fuzz/invariant tests for respective contracts. They contain helper internal functions to help in testing.

**helpers:** Helper contracts for mock contracts, to enable interacting with mock contracts. It is recommended to use respective helper contract to interact with mocks.

**deployers:** Deployer contract for respective contract, containing function for deploying target contract, this needs to be extended by test contract which wants to use or test target contract.

**libraries:** Tests for library contracts. It contains fuzz and concrete tests, both for target library.

**concrete:** Concrete tests are used to unit test target contract with hard coded values.

**fuzz:** Fuzz tests are used to test public functions in target contracts like HOT.

**mocks:** Mock contracts used to simulate different behaviour for different components.

## Demo

To run demo of Hot swap using scripts in `scripts/hot-example/`, use following command in terminal, after running yarn.

Note: Remember to approve the token transfers to the Sovereign Pool address, before running the scripts.

```
# To run demo using viem
API_KEY=<HOT_API_KEY> PK=<PRIVATE_KEY> GNOSIS_RPC=<RPC_URL> yarn demo-viem:HOT
# To run demo using ethers
API_KEY=<HOT_API_KEY> PK=<PRIVATE_KEY> GNOSIS_RPC=<RPC_URL> yarn demo-ethers:HOT
```
