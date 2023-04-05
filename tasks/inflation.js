/* eslint-disable no-undef */
// hardhat ensures hre is always in scope, no need to require
const { utils } = require("ethers");
const { get, log, logtx, getNamedAccounts, now } = require("./lib/utils");

task("inflation:canCycleStart", "Can a new rewards cycle start")
	.addParam("actor", "Account used to send tx")
	.setAction(async ({ actor }) => {
		const signer = (await getNamedAccounts())[actor];
		const rewardsPool = await get("RewardsPool", signer);
		const canStart = await rewardsPool.canStartRewardsCycle();
		log(`Can a new rewards cycle start?: ${canStart}`);
	});

task("inflation:cycleStatus", "How many rewards cycles have passed").setAction(
	async () => {
		const rewardsPool = await get("RewardsPool");
		const dao = await get("ProtocolDAO");
		log(`now?: ${await now()}`);
		log(`dao.getRewardsCycleSeconds: ${await dao.getRewardsCycleSeconds()}`);
		log(
			`RewardsCycleStartTime: ${await rewardsPool.getRewardsCycleStartTime()}`
		);
		log(`RewardsCycleTotalAmt: ${await rewardsPool.getRewardsCycleTotalAmt()}`);
		log(
			`InflationIntervalStartTime: ${await rewardsPool.getInflationIntervalStartTime()}`
		);
		log(
			`InflationAmt (currentSupply, nextSupply): ${await rewardsPool.getInflationAmt()}`
		);
		log(`RewardsCyclesElapsed: ${await rewardsPool.getRewardsCyclesElapsed()}`);
		log(
			`InflationIntervalsElapsed: ${await rewardsPool.getInflationIntervalsElapsed()}`
		);
	}
);

// be sure to skip ahead 2 days for this to work successfully
task("inflation:startRewardsCycle", "start a new rewards cycle")
	.addParam("actor", "Account used to send tx")
	.setAction(async ({ actor }) => {
		const signer = (await getNamedAccounts())[actor];
		const rewardsPool = await get("RewardsPool", signer);
		const canStart = await rewardsPool.canStartRewardsCycle();
		if (!canStart) {
			log("canStartRewardsCycle() is false");
			return;
		}
		tx = await rewardsPool.startRewardsCycle();
		await logtx(tx);
		// log how much was distributed to each contract and total
		const totalRewardsThisCycle = utils.formatEther(
			`${await rewardsPool.getRewardsCycleTotalAmt()}`
		);
		const daoAllowance = utils.formatEther(
			`${await rewardsPool.getClaimingContractDistribution("ClaimProtocolDAO")}`
		);
		const nopClaimContractAllowance = utils.formatEther(
			`${await rewardsPool.getClaimingContractDistribution("ClaimNodeOp")}`
		);
		log(
			`Total Rewards this cycle: ${totalRewardsThisCycle} GGP. Rewards transferred to the Protocol DAO: ${daoAllowance} GGP. Rewards transferred to the ClaimNodeOp: ${nopClaimContractAllowance} GGP`
		);
	});

// Will need to do this before you can start cycle
task(
	"inflation:transferGGP",
	"transfer GGP to the vault from the deployer"
).setAction(async () => {
	const dao = await get("ProtocolDAO");
	const ggp = await get("TokenGGP");
	const vault = await get("Vault");
	const currentAmt = await vault.balanceOfToken("RewardsPool", ggp.address);

	const rewardsAmt = (await ggp.totalSupply()).sub(
		await dao.getTotalGGPCirculatingSupply()
	);

	if (currentAmt >= rewardsAmt) return;

	tx = await ggp.approve(vault.address, rewardsAmt);
	await logtx(tx);
	tx = await vault.depositToken("RewardsPool", ggp.address, rewardsAmt);
	await logtx(tx);
	const transferredAmt = await vault.balanceOfToken("RewardsPool", ggp.address);

	log(`Rewards Pool now contains ${transferredAmt} GGP`);
});
