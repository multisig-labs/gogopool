/* eslint-disable no-undef */
// hardhat ensures hre is always in scope, no need to require
const { task } = require("hardhat/config");
const {
	get,
	overrides,
	log,
	logtx,
	nodeID,
	getNamedAccounts,
	getMinipoolsFor,
	hash,
	logMinipools,
	parseDelta,
	now,
	nodeIDToHex,
} = require("./lib/utils");

task("minipool:create-all", "")
	.addParam("actor", "Account used to send tx")
	.setAction(async ({ actor }) => {
		const nodeIDs = [
			"NodeID-KxYN51D4Hb5SoMNGWNW1wGBNH4SrjHpP3",
			"NodeID-A4YhHAFqWwV4KUE6vE7H642JTcMeMHdc4",
			"NodeID-BV7J8M1sfd1psdv8HUVXgmV3J5kYKCWwj",
			"NodeID-9RFwDyrF4ZnPWMYJZvkCpXJJTggdzDnGH",
			"NodeID-GyAJjJqPmzAAEQ9L45mYNrQaabSz9UjDP",
			"NodeID-D1nyVPZoC8BZvjhfUq4jGa8sFQrMRXUuZ",
			"NodeID-KYv4pxV3ojKvb4HjDdozsAMffSkZ388kn",
			"NodeID-QJ7By6xr6o1KrQqoxFFguncPNNPULDt5Z",
			"NodeID-BD2Z9YFPZkHu2VDLGCm9fYLahkwvn4kum",
			"NodeID-54FxTyMmPKCDMEZz3AouCi4LL9yZKyM77",
			"NodeID-9ZEJWemTBohJZY64E8Xgq85S4rHrZ4sQj",
		];

		// for (node of nodeIDs) {
		// 	console.log(nodeIDToHex(node));
		// }
		// return;

		const amt = 100_000;

		const signer = (await getNamedAccounts())[actor];
		const minipoolManager = await get("MinipoolManager", signer);
		// const staking = await get("Staking", signer);
		// const ggp = await get("TokenGGP", signer);

		// await hre.run("debug:topup_actor_balance", { actor, amt });
		// await hre.run("ggp:deal", { recip: actor, amt: amt });

		// let tx = await ggp.approve(
		// 	staking.address,
		// 	ethers.utils.parseEther(amt.toString())
		// );
		// await tx.wait();
		// tx = await staking.stakeGGP(ethers.utils.parseEther(amt.toString()));
		// await tx.wait();

		for (const node of nodeIDs) {
			console.log(node);
			try {
				await minipoolManager.callStatic.createMinipool(
					nodeID(node),
					parseDelta("2m"),
					20_000,
					hre.ethers.utils.parseEther("1000"),
					{ ...overrides, value: hre.ethers.utils.parseEther("1000") }
				);
				tx = await minipoolManager.createMinipool(
					nodeID(node),
					parseDelta("2m"),
					20_000,
					hre.ethers.utils.parseEther("1000"),
					{ ...overrides, value: hre.ethers.utils.parseEther("1000") }
				);
				await logtx(tx);
				log(`Minipool created for node ${node}: ${nodeID(node)}`);
			} catch (err) {
				log("ERROR", err);
			}
		}
	});

task("minipool:list", "List all minipools").setAction(async () => {
	for (let status = 0; status <= 6; status++) {
		const mps = await getMinipoolsFor(status);
		if (mps.length > 0) logMinipools(mps);
	}
});

task("minipool:list_claimable", "List all claimable minipools")
	.addParam("actor", "multisig name")
	.setAction(async ({ actor }) => {
		const signer = (await getNamedAccounts())[actor];
		const minipools = await getMinipoolsFor(0, signer.address);

		// Somehow Rialto will sort these by priority
		logMinipools(minipools);
	});

task("minipool:create", "")
	.addParam("actor", "Account used to send tx")
	.addParam("node", "Real NodeID or name to use as a random seed")
	.addParam("duration", "Duration", "14d", types.string)
	.addParam("fee", "2% is 20,000", 20000, types.int)
	.addParam("avax", "Amt of AVAX to send (units are AVAX)", "1000")
	.addParam("avaxRequested", "Amt of AVAX to request (units are AVAX)", "1000")
	.setAction(async ({ actor, node, duration, fee, avax, avaxRequested }) => {
		const signer = (await getNamedAccounts())[actor];
		const minipoolManager = await get("MinipoolManager", signer);
		await minipoolManager.callStatic.createMinipool(
			nodeID(node),
			parseDelta(duration),
			fee,
			hre.ethers.utils.parseEther(avaxRequested),
			{ ...overrides, value: hre.ethers.utils.parseEther(avax) }
		);
		tx = await minipoolManager.createMinipool(
			nodeID(node),
			parseDelta(duration),
			fee,
			hre.ethers.utils.parseEther(avaxRequested),
			{ ...overrides, value: hre.ethers.utils.parseEther(avax) }
		);
		await logtx(tx);
		log(`Minipool created for node ${node}: ${nodeID(node)}`);
	});

task("minipool:update_status", "Force into a particular status")
	.addParam("actor", "Account used to send tx")
	.addParam("node", "NodeID name")
	.addParam("status", "", 0, types.int)
	.setAction(async ({ actor, node, status }) => {
		const signer = (await getNamedAccounts())[actor];
		const minipoolManager = await get("MinipoolManager", signer);
		tx = await minipoolManager.updateMinipoolStatus(nodeID(node), status);
		await logtx(tx);
		log(`Minipool status updated to ${status} for ${node}`);
	});

task("minipool:cancel", "")
	.addParam("actor", "Account used to send tx")
	.addParam("node", "NodeID name")
	.setAction(async ({ actor, node }) => {
		const signer = (await getNamedAccounts())[actor];
		const minipoolManager = await get("MinipoolManager", signer);
		tx = await minipoolManager.cancelMinipool(nodeID(node));
		await logtx(tx);
		log(`Minipool canceled`);
	});

task("minipool:can_claim", "")
	.addParam("actor", "Account used to send tx")
	.addParam("node", "NodeID name", "")
	.setAction(async ({ actor, node }) => {
		const signer = (await getNamedAccounts())[actor];
		const minipoolManager = await get("MinipoolManager", signer);
		const res = await minipoolManager.canClaimAndInitiateStaking(
			nodeID(node),
			overrides
		);
		log(`Can claim ${node}: ${res}`);
	});

task("minipool:claim", "Claim minipools until funds run out")
	.addParam("actor", "Account used to send tx")
	.setAction(async ({ actor }) => {
		const signer = (await getNamedAccounts())[actor];
		const minipoolManager = await get("MinipoolManager", signer);

		const prelaunchStatus = 0;
		const minipools = await getMinipoolsFor(prelaunchStatus, signer.address); // 0=Prelaunch

		if (minipools.length === 0) {
			console.log("no minipools to claim");
		}

		// Somehow Rialto will sort these by priority
		for (mp of minipools) {
			const canClaim = await minipoolManager.canClaimAndInitiateStaking(
				mp.nodeID,
				overrides
			);
			if (canClaim) {
				log(`Claiming ${mp.nodeID}`);
				tx = await minipoolManager.claimAndInitiateStaking(
					mp.nodeID,
					overrides
				);
				await logtx(tx);
			} else {
				log("Nothing to do or not enough user funds");
			}
		}
	});

task("minipool:claim_one", "")
	.addParam("actor", "Account used to send tx")
	.addParam("node", "NodeID name")
	.setAction(async ({ actor, node }) => {
		const signer = (await getNamedAccounts())[actor];
		const minipoolManager = await get("MinipoolManager", signer);
		const canClaim = await minipoolManager.canClaimAndInitiateStaking(
			nodeID(node),
			overrides
		);
		if (canClaim) {
			tx = await minipoolManager.claimAndInitiateStaking(
				nodeID(node),
				overrides
			);
			await logtx(tx);
			log(`Minipool claimed for ${node}`);
		} else {
			log("canClaimAndInitiateStaking returned false");
		}
	});

task("minipool:recordStakingStart", "")
	.addParam("actor", "Account used to send tx")
	.addParam("node", "NodeID name")
	.addParam("start", "staking start time", 0, types.int)
	.addParam("txid", "txid of AddValidatorTx", "", types.string)
	.setAction(async ({ actor, node, start, txid }) => {
		if (start === 0) {
			start = await now();
		}
		if (txid === "") {
			txid = hre.ethers.constants.HashZero;
		}
		const signer = (await getNamedAccounts())[actor];
		const minipoolManager = await get("MinipoolManager", signer);
		let tx = await minipoolManager.callStatic.recordStakingStart(
			nodeID(node),
			txid,
			start,
			overrides
		);
		tx = await minipoolManager.recordStakingStart(
			nodeID(node),
			txid,
			start,
			overrides
		);
		await logtx(tx);
	});

task("minipool:getIndexOf", "")
	.addParam("node", "id of node")
	.setAction(async ({ node }) => {
		const minipoolManager = await get("MinipoolManager");
		const i = await minipoolManager.getIndexOf(nodeID(node));
		console.log("node id", nodeID(node));
		console.log("index", i);
	});

task("minipool:getMinipoolByNodeID", "")
	.addParam("node", "id of node")
	.setAction(async ({ node }) => {
		const minipoolManager = await get("MinipoolManager");
		const mp = await minipoolManager.getMinipoolByNodeID(nodeID(node));
		console.log("node id", nodeID(node));
		console.log("mp", mp);
		logMinipools([mp]);
	});

task("minipool:recordStakingEnd", "")
	.addParam("actor", "Account used to send tx")
	.addParam("node", "NodeID")
	.addParam("reward", "AVAX Reward amount", 0, types.int)
	.setAction(async ({ actor, node, reward }) => {
		reward = hre.ethers.utils.parseEther(reward.toString());
		const signer = (await getNamedAccounts())[actor];
		const minipoolManager = await get("MinipoolManager", signer);
		const i = await minipoolManager.getIndexOf(nodeID(node));
		const mp = await minipoolManager.getMinipool(i);
		const end = mp.startTime.add(mp.duration);
		const avax = mp.avaxNodeOpAmt.add(mp.avaxLiquidStakerAmt);

		// Send rialto the reward funds from some other address to simulate Avalanche rewards,
		// so we can see rialto's actual balance
		const rewarder = (await getNamedAccounts()).rewarder;
		const sendTx = {
			to: signer.address,
			value: reward,
		};
		tx = await rewarder.sendTransaction(sendTx);
		await logtx(tx);

		total = avax.add(reward);

		tx = await minipoolManager.callStatic.recordStakingEnd(
			nodeID(node),
			end,
			reward,
			{
				...overrides,
				value: total,
			}
		);
		tx = await minipoolManager.recordStakingEnd(nodeID(node), end, reward, {
			...overrides,
			value: total,
		});
		await logtx(tx);
	});

task("minipool:withdrawMinipoolFunds", "")
	.addParam("actor", "Account used to send tx")
	.addParam("node", "NodeID name")
	.setAction(async ({ actor, node }) => {
		const signer = (await getNamedAccounts())[actor];
		const minipoolManager = await get("MinipoolManager", signer);
		tx = await minipoolManager.withdrawMinipoolFunds(nodeID(node));
		await logtx(tx);
	});

task("minipool:expected_reward", "")
	.addParam("duration", "duration of validation period")
	.addParam("amt", "AVAX amount", 0, types.int)
	.setAction(async ({ duration, amt }) => {
		parsedAmt = ethers.utils.parseEther(amt.toString());
		parsedDuration = parseDelta(duration);
		const minipoolManager = await get("MinipoolManager");
		const expectedAmt = await minipoolManager.expectedRewardAmt(
			parsedDuration,
			parsedAmt
		);
		log(
			`${amt} of AVAX staked for ${duration} should yield ${hre.ethers.utils.formatUnits(
				expectedAmt
			)} AVAX`
		);
	});

task("minipool:calculate_slash", "")
	.addParam("amt", "Expected AVAX reward amount", 0, types.int)
	.setAction(async ({ amt }) => {
		parsedAmt = ethers.utils.parseEther(amt.toString());
		console.log(parsedAmt);
		const minipoolManager = await get("MinipoolManager");
		const slashAmt = await minipoolManager.calculateSlashAmt(parsedAmt);
		log(
			`${amt} AVAX is equivalent to ${hre.ethers.utils.formatEther(
				slashAmt
			)} GGP at current prices`
		);
	});

task("minipool:set_multisig", "switch a node to a specified multisig or EOA")
	.addParam("node")
	.addParam("addr")
	.setAction(async ({ node, addr }) => {
		const signer = (await getNamedAccounts())["deployer"];
		const store = await get("Storage", signer);
		const minipoolManager = await get("MinipoolManager", signer);
		const i = await minipoolManager.getIndexOf(nodeID(node));
		const tx = await store.setAddress(
			hash(["string", "int", "string"], ["minipool.item", i, ".multisigAddr"]),
			ethers.utils.getAddress(addr)
		);
		await logtx(tx);
	});
// task("minipool:queue", "List all minipools in the queue").setAction(
// 	async () => {
// 		const MINIPOOL_QUEUE_KEY = hash(["string"], ["minipoolQueue"]);

// 		const storage = await get("Storage");
// 		const start = await storage.getUint(
// 			hash(["bytes32", "string"], [MINIPOOL_QUEUE_KEY, ".start"])
// 		);
// 		const end = await storage.getUint(
// 			hash(["bytes32", "string"], [MINIPOOL_QUEUE_KEY, ".end"])
// 		);
// 		const minipoolQueue = await get("BaseQueue");
// 		const len = await minipoolQueue.getLength(MINIPOOL_QUEUE_KEY);
// 		log(`Queue start: ${start}  end: ${end}  len: ${len}`);
// 		for (let i = start; i < end; i++) {
// 			try {
// 				const nodeID = await minipoolQueue.getItem(MINIPOOL_QUEUE_KEY, i);
// 				if (nodeID === hre.ethers.constants.AddressZero) break;
// 				log(`[${i}] ${nodeID}`);
// 			} catch (e) {
// 				log("error", e);
// 			}
// 		}
// 	}
// );
