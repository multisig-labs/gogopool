import * as dotenv from "dotenv";
import * as fs from "fs";
import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "@atixlabs/hardhat-time-n-mine";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-preprocessor";
import "hardhat-storage-layout";

dotenv.config();

// Load tasks
const files = fs.readdirSync("./tasks");
for (const file of files) {
	if (!file.endsWith(".js")) continue;
	require(`./tasks/${file}`);
}

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

// "custom" network is what ANR calls itself, so we use that terminology

function getRemappings() {
	return fs
		.readFileSync("remappings.txt", "utf8")
		.split("\n")
		.filter(Boolean)
		.map((line) => line.trim().split("="));
}

const config: HardhatUserConfig = {
	solidity: {
		version: "0.8.17",
		settings: {
			optimizer: {
				enabled: true,
				runs: 1000,
			},
		},
	},
	defaultNetwork: "custom",
	networks: {
		hardhat: {
			chainId: 43112,
			accounts: {
				mnemonic: process.env.MNEMONIC || "MISSING ENV MNEMONIC!",
				accountsBalance: "1000000000000000000000000",
			},
		},
		custom: {
			url: process.env.ETH_RPC_URL,
			gasPrice: 225000000000,
			chainId: 43112,
			accounts: {
				mnemonic: process.env.MNEMONIC || "MISSING ENV MNEMONIC!",
			},
		},
		fuji: {
			url: "https://api.avax-test.network/ext/bc/C/rpc",
			gasPrice: 225000000000,
			chainId: 43113,
			accounts: {
				mnemonic: process.env.MNEMONIC || "MISSING ENV MNEMONIC!",
			},
		},
		mainnet: {
			url: "https://api.avax.network/ext/bc/C/rpc",
			gasPrice: 225000000000,
			chainId: 43114,
			accounts: {
				mnemonic: process.env.MNEMONIC || "MISSING ENV MNEMONIC!",
			},
		},
	},
	gasReporter: {
		enabled: process.env.REPORT_GAS !== undefined,
		currency: "USD",
	},
	etherscan: {
		apiKey: process.env.ETHERSCAN_API_KEY,
	},
	preprocess: {
		eachLine: (hre) => ({
			transform: (line: string) => {
				if (line.match(/^\s*import /i)) {
					getRemappings().forEach(([find, replace]) => {
						if (line.match(find)) {
							line = line.replace(find, replace);
						}
					});
				}
				return line;
			},
		}),
	},
	paths: {
		sources: "./contracts",
		cache: "./cache",
	},
};

export default config;
