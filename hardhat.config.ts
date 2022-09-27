require('dotenv').config({path:__dirname+'/.env'})
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "solidity-coverage";
import "hardhat-gas-reporter";
import "@nomiclabs/hardhat-etherscan";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    }
  },
  gasReporter: {
    enabled: true,
    coinmarketcap: "e29889b1-79bf-405b-bb1c-6febc583c3f7"
  },
  networks: {
    bscTestnet: {
      url: "https://warmhearted-alien-orb.bsc-testnet.quiknode.pro/8d67504adbd1ffd36579ec5ac682640dd753d223/",
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    }
  },
  etherscan: {
    apiKey: {
      bsc: "YYC9YZP7PFB3UFW3YY8I33VBISCFSPJSY9",
      bscTestnet: "YYC9YZP7PFB3UFW3YY8I33VBISCFSPJSY9"
    }
  }
};


export default config;
