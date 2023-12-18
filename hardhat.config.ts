import fs from 'fs';
import '@nomicfoundation/hardhat-toolbox';
import 'hardhat-preprocessor';
import { HardhatUserConfig } from 'hardhat/config';

import 'dotenv/config';

function getRemappings() {
  return fs
    .readFileSync('remappings.txt', 'utf8')
    .split('\n')
    .filter(Boolean) // remove empty lines
    .map((line) => line.trim().split('='));
}

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.19',
        settings: { optimizer: { enabled: true, runs: 20000 } },
      },
    ],
  },
  networks: {
    hardhat: {
      forking: {
        url: process.env.MAINNET_URL!,
      },
    },
  },
  preprocess: {
    eachLine: (_hre) => ({
      transform: (line: string) => {
        if (line.match(/^\s*import /i)) {
          for (const [from, to] of getRemappings()) {
            if (line.includes(from)) {
              line = line.replace(from, to);
              break;
            }
          }
        }
        return line;
      },
    }),
  },
  paths: {
    sources: './src',
    cache: './cache_hardhat',
  },
};

export default config;
