/* eslint-disable no-undef */
// hardhat ensures hre is always in scope, no need to require
const { task } = require("hardhat/config");
const {
	addrs,
	get,
	hash,
	log,
	logf,
	logtx,
	getNamedAccounts,
	now,
	nodeID,
	nodeHexToID,
} = require("./lib/utils");
const { writeFile } = require("node:fs/promises");

///
task(
	"debug:setup",
	"Run after a local deploy to init necessary configs"
).setAction(async () => {
	const oneinch = await get("OneInchMock");
	await hre.run("vault:register_allowed_tokens");
	await hre.run("oracle:set_oneinch", { addr: oneinch.address });
	await hre.run("debug:topup_actor_balances", { amt: 50000 });
	await hre.run("ggp:deal", { recip: "nodeOp1", amt: 10000 });
	await hre.run("ggavax:liqstaker_deposit_avax", {
		actor: "alice",
		amt: 10000,
	});
	await hre.run("ggavax:liqstaker_deposit_avax", { actor: "bob", amt: 10000 });
	await hre.run("multisig:register", { name: "rialto1" });
	await hre.run("oracle:set_ggp", { actor: "rialto1", price: "1" });
	await hre.run("inflation:transferGGP");
	await hre.run("inflation:startRewardsCycle", { actor: "rialto1" });
});

task(
	"debug:setup-dao",
	"Run after a ARN testnet deploy to init necessary DAO configs"
).setAction(async () => {
	const store = await get("Storage");
	let tx;
	tx = await store.setUint(
		hash(["string"], ["ProtocolDAO.InflationIntervalSeconds"]),
		ethers.BigNumber.from("60")
	);
	await logtx(tx);

	tx = await store.setUint(
		hash(["string"], ["ProtocolDAO.InflationIntervalRate"]),
		// 50% annual inflation with 1min periods
		// (1 + targetAnnualRate) ** (1 / intervalsPerYear) * 1000000000000000000
		ethers.BigNumber.from("1000000771433151600")
	);
	await logtx(tx);

	tx = await store.setUint(
		hash(["string"], ["ProtocolDAO.RewardsEligibilityMinSeconds"]),
		ethers.BigNumber.from("1")
	);
	await logtx(tx);

	tx = await store.setUint(
		hash(["string"], ["ProtocolDAO.RewardsCycleSeconds"]),
		ethers.BigNumber.from("600")
	);
	await logtx(tx);
});

task(
	"debug:setup_anr_accounts",
	"Run against a fresh ANR instance (before a deploy) to xfer all genesis funds to a deployer addr derived from the mnemonic"
).setAction(async () => {
	// Get all signers from mnemonic in hardhat.config
	const signers = await hre.ethers.getSigners();
	const deployer = signers[0];
	const rewarder = signers[1];

	// Genesis key for ANR "local"/"custom" network
	//   Private Key: 0x56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027
	//   Address: 0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC
	const defaultANRPK =
		"0x56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027";
	const defaultANR = new hre.ethers.Wallet(defaultANRPK, hre.ethers.provider);
	let bal = await defaultANR.getBalance();
	log(`Default ANR account balance: ${hre.ethers.utils.formatUnits(bal)}`);
	if (bal.lt(ethers.utils.parseEther("10", "ether"))) {
		log("Looks like balance was already transferred out, skipping...");
		return;
	}
	const rewarderAmt = ethers.utils.parseEther("1000000", "ether");
	console.log(
		`Sending ${hre.ethers.utils.formatUnits(rewarderAmt)} to new rewarder ${
			rewarder.address
		}`
	);
	let tx = await defaultANR.sendTransaction({
		to: rewarder.address,
		value: rewarderAmt,
	});
	await logtx(tx);

	bal = await defaultANR.getBalance();
	console.log(
		`Sending remaining balance ${hre.ethers.utils.formatUnits(
			bal
		)} to new deployer ${deployer.address}`
	);
	tx = await defaultANR.sendTransaction({
		to: deployer.address,
		value: bal.sub(ethers.utils.parseEther("1", "ether")),
	});
	await logtx(tx);
});

task("debug:skip", "Skip forward a duration")
	.addParam("duration", "")
	.setAction(async ({ duration }) => {
		await hre.run("setTimeIncrease", { delta: duration });
		await hre.run("mine");
	});

task("debug:topup_actor_balance")
	.addParam("actor", "")
	.addParam("amt", "", 0, types.int)
	.setAction(async ({ actor, amt }) => {
		const actors = await getNamedAccounts();
		const signer = actors.deployer;
		const a = actors[actor];
		const balAVAX = await hre.ethers.provider.getBalance(a.address);
		const desiredBalAVAX = ethers.utils.parseEther(amt.toString());
		const txs = [];
		if (balAVAX.lt(desiredBalAVAX)) {
			log(`Topping up ${actor}`);
			const tx = await signer.sendTransaction({
				to: a.address,
				value: desiredBalAVAX.sub(balAVAX),
			});
			txs.push(logtx(tx));
		}
		await Promise.all(txs);
	});

task("debug:topup_actor_balances")
	.addParam("amt", "", 0, types.int)
	.setAction(async ({ amt }) => {
		const actors = await getNamedAccounts();
		for (actor in actors) {
			await hre.run("debug:topup_actor_balance", { amt, actor });
		}
	});

task("debug:list_contract_balances").setAction(async () => {
	const actors = await getNamedAccounts();
	const ggAVAX = await get("TokenggAVAX");
	const ggp = await get("TokenGGP");

	log("");
	logf(
		"%-16s %-42s %-20s %-20s %-20s %-20s",
		"User",
		"Address",
		"AVAX",
		"ggAVAX",
		"equivAVAX",
		"GGP"
	);
	for (const name in addrs) {
		const balAVAX = await hre.ethers.provider.getBalance(addrs[name]);
		const balGGAVAX = await ggAVAX.balanceOf(addrs[name]);
		const balEQAVAX = await ggAVAX.previewRedeem(balGGAVAX);
		const balGGP = await ggp.balanceOf(addrs[name]);
		logf(
			"%-16s %-42s %-20.5f %-20.5f %-20.5f %-20.5f",
			name,
			addrs[name],
			hre.ethers.utils.formatUnits(balAVAX),
			hre.ethers.utils.formatUnits(balGGAVAX),
			hre.ethers.utils.formatUnits(balEQAVAX),
			hre.ethers.utils.formatUnits(balGGP)
		);
	}
});

task("debug:list_actor_balances").setAction(async () => {
	const actors = await getNamedAccounts();
	const ggAVAX = await get("TokenggAVAX");
	const ggp = await get("TokenGGP");

	log("");
	logf(
		"%-10s %-42s %-20s %-20s %-20s %-20s",
		"User",
		"Address",
		"AVAX",
		"ggAVAX",
		"equivAVAX",
		"GGP"
	);
	for (actor in actors) {
		const balAVAX = await hre.ethers.provider.getBalance(actors[actor].address);
		const balGGAVAX = await ggAVAX.balanceOf(actors[actor].address);
		const balEQAVAX = await ggAVAX.previewRedeem(balGGAVAX);
		const balGGP = await ggp.balanceOf(actors[actor].address);
		logf(
			"%-10s %-42s %-20.5f %-20.5f %-20.5f %-20.5f",
			actor,
			actors[actor].address,
			hre.ethers.utils.formatUnits(balAVAX),
			hre.ethers.utils.formatUnits(balGGAVAX),
			hre.ethers.utils.formatUnits(balEQAVAX),
			hre.ethers.utils.formatUnits(balGGP)
		);
	}
});

task("debug:list_vars", "List important system variables").setAction(
	async () => {
		const curTs = await now();
		log(`Current block.timestamp: ${curTs}`);

		const vault = await get("Vault");
		const ggAVAX = await get("TokenggAVAX");

		await hre.run("multisig:list");
		log("");

		let bal;
		logf("%-20s %-10s", "Contract", "AVAX Balance");
		for (const name of ["MinipoolManager", "TokenggAVAX"]) {
			bal = await vault.balanceOf(name);
			logf("%-20s %-10d", name, hre.ethers.utils.formatUnits(bal));
		}

		log("");
		log("ggAVAX Variables:");
		const rewardsCycleEnd = await ggAVAX.rewardsCycleEnd();
		const lastRewardsAmount = await ggAVAX.lastRewardsAmt();
		const networkTotalAssets = await ggAVAX.totalReleasedAssets();
		const stakingTotalAssets = await ggAVAX.stakingTotalAssets();
		const amountAvailableForStaking = await ggAVAX.amountAvailableForStaking();
		const totalAssets = await ggAVAX.totalAssets();
		logf(
			"%-15s %-15s %-15s %-15s %-15s %-15s",
			"rwdCycEnd",
			"lstRwdAmt",
			"totRelAss",
			"stakTotAss",
			"AmtAvlStak",
			"totAssets"
		);
		logf(
			"%-15s %-15.5f %-15.5f %-15.5f %-15.5f %-15.5f",
			rewardsCycleEnd,
			hre.ethers.utils.formatUnits(lastRewardsAmount),
			hre.ethers.utils.formatUnits(networkTotalAssets),
			hre.ethers.utils.formatUnits(stakingTotalAssets),
			hre.ethers.utils.formatUnits(amountAvailableForStaking),
			hre.ethers.utils.formatUnits(totalAssets)
		);

		log("");
		const oracle = await get("Oracle");
		const oracleResults = await oracle.getGGPPriceInAVAX();
		const ggpPrice = await oracleResults.price;
		const ggpTs = await oracleResults.timestamp;
		log(
			`Oracle GGP Price: ${hre.ethers.utils.formatUnits(ggpPrice)} at ${ggpTs}`
		);
	}
);

task(
	"debug:list_contracts",
	"List all contracts that are registered in storage and refresh ./cache/deployed_addrs_[network].json"
).setAction(async () => {
	const storage = await get("Storage");
	for (const name in addrs) {
		try {
			const address = await storage.getAddress(
				hash(["string", "string"], ["contract.address", name])
			);
			const n = await storage.getString(
				hash(["string", "address"], ["contract.name", address])
			);
			const exists = await storage.getBool(
				hash(["string", "address"], ["contract.exists", address])
			);
			const emoji = exists && n === name ? "✅" : "(Not Registered)";
			if (address !== hre.ethers.constants.AddressZero) {
				logf("%-40s, %-30s, %s", name, address, emoji);
				addrs[name] = address; // update local cache with whats in storage
			} else {
				logf("%-40s, %-30s", name, addrs[name]);
			}
		} catch (e) {
			log("error", e);
		}
	}

	// // Write out the deployed addresses to a format easily loaded by bash for use by cast
	// let data = "declare -A addrs=(";
	// for (const name in addrs) {
	// 	data = data + `[${name}]="${addrs[name]}" `;
	// }
	// data = data + ")";
	// await writeFile(`cache/deployed_addrs_${network.name}.bash`, data);

	// // Write out the deployed addrs to a format easily loaded by javascript
	// data = `module.exports = ${JSON.stringify(addrs, null, 2)}`;
	// await writeFile(`cache/deployed_addrs_${network.name}.js`, data);

	// // Write out the deployed addrs to json (used by Rialto during dev)
	// data = JSON.stringify(addrs, null, 2);
	// await writeFile(`cache/deployed_addrs_${network.name}.json`, data);
});

task("debug:node_ids")
	.addParam("name", "either NodeID-123, 0x123, or a name like 'node1'")
	.setAction(async ({ name }) => {
		addr = nodeID(name);
		out = {
			nodeAddr: addr,
			nodeID: nodeHexToID(addr),
		};
		console.log(JSON.stringify(out));
	});

// Take users we are using for ANR and make a standard JSON all tools can use
task("debug:output_named_users").setAction(async () => {
	// Get mnemonic from the hardhat config (which gets it from the ENV)
	const cfg = hre.config.networks.custom.accounts;
	const HDNode = hre.ethers.utils.HDNode.fromMnemonic(cfg.mnemonic);

	// Using the mnemonic, iterate through the derived addresses/privateKeys
	const pks = {};
	for (let i = 0; i < 20; i++) {
		const derivedNode = HDNode.derivePath(`${cfg.path}/${i}`);
		pks[derivedNode.address] = derivedNode.privateKey;
	}

	const signers = await getNamedAccounts();

	const out = {};
	for (s in signers) {
		out[s] = {
			pk: pks[signers[s].address],
			address: signers[s].address,
		};
	}
	console.log(`addresses and keys for mnemonic: ${HDNode.mnemonic.phrase}`);
	console.log(JSON.stringify(out, null, 2));
});
