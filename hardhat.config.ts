import * as dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/config";

import "@nomicfoundation/hardhat-chai-matchers";
import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "@openzeppelin/hardhat-upgrades";
import "@typechain/hardhat";

import "hardhat-deploy";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "solidity-docgen";
import "hardhat-contract-sizer";
dotenv.config();

const config: HardhatUserConfig = {
  gasReporter: {
    enabled: false
  },
  solidity: {
    compilers: [
      {
        version: "0.8.20", settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.13", settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.4.18", settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.6.6", settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.5.16", settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.6.12", settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ]
  },
  networks: {
    hardhat: {
      // allowUnlimitedContractSize: true,
      loggingEnabled: false,
      saveDeployments: false,
      live: false,
    },
    sepolia: {
      url: "https://rpc2.sepolia.org",
      chainId: 11155111,
      live: true,
      accounts: process.env.DEPLOYER_PRIVATE_KEY ? [`0x${process.env.DEPLOYER_PRIVATE_KEY}`] : [],
    },
    mantle: {
      url: "https://mantle.drpc.org",
      chainId: 5000,
      live: true,
      accounts: process.env.DEPLOYER_PRIVATE_KEY ? [`0x${process.env.DEPLOYER_PRIVATE_KEY}`] : [],
    },
    mantle_sepolia: {
      url: "https://rpc.sepolia.mantle.xyz",
      chainId: 5003,
      live: true,
      accounts: process.env.DEPLOYER_PRIVATE_KEY ? [`0x${process.env.DEPLOYER_PRIVATE_KEY}`] : [],
    },
  },
  // Hardhat deploy
  namedAccounts: {
    deployer: 0,
    acc1: 1,
    acc2: 2,
    proxyAdmin: 3,
    acc3: 4,
    SwapRouter: 5
  },
  mocha: {
    timeout: 2000000,
  },
}

export default config;