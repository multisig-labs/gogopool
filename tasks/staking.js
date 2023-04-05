/* eslint-disable no-undef */
// hardhat ensures hre is always in scope, no need to require
const { task } = require("hardhat/config");
const {
	get,
	getNamedAccounts,
	logf,
	getStakers,
	logStakers,
} = require("./lib/utils");

task("staking:info", "Staking protocol info").setAction(async () => {
	const staking = await get("Staking");
	const totalStake = await staking.getTotalGGPStake();
	logf(
		"%-15s %-15s",
		"Total GGP Staked:",
		ethers.utils.formatUnits(totalStake)
	);
	logf("%-15s %-15s", "Total Stakers:", await staking.getStakerCount());
});

task("staking:get_ggp_stake", "get actors stake amount")
	.addParam("actor", "Actor to get stake")
	.setAction(async ({ actor }) => {
		const signer = (await getNamedAccounts())[actor];
		const staking = await get("Staking");
		const stake = await staking.getGGPStake(signer.address);
		console.log("stake is ", stake);
	});

task("staking:staker_info", "GGP staking info for actor")
	.addParam("actor", "Actor to check stake")
	.setAction(async ({ actor }) => {
		const signer = (await getNamedAccounts())[actor];
		const staking = await get("Staking");
		const idx = await staking.getIndexOf(signer.address);
		const staker = await staking.getStaker(idx);
		logf(
			"%-15s %-15s",
			"GGP Staked:",
			ethers.utils.formatUnits(staker.ggpStaked)
		);
		logf(
			"%-15s %-15s",
			"AVAX Staked:",
			ethers.utils.formatUnits(staker.avaxStaked)
		);
		logf(
			"%-15s %-15s",
			"AVAX Assigned:",
			ethers.utils.formatUnits(staker.avaxAssigned)
		);
	});

task("staking:get_user_min_stake", "Minimum GGP stake required for actor")
	.addParam("actor", "Balance to check")
	.setAction(async ({ actor }) => {
		const signer = (await getNamedAccounts())[actor];
		const staking = await get("Staking");

		const minStakeAmt = await staking.getUserMinimumGGPStake(signer.address);
		console.log("Min stake amount", ethers.utils.formatUnits(minStakeAmt));
	});

task("staking:stake_ggp", "Stake ggp for actor")
	.addParam("actor", "Account used to send tx")
	.addParam("amt", "Amount of ggp to stake", 0, types.int)
	.setAction(async ({ actor, amt }) => {
		const signer = (await getNamedAccounts())[actor];
		const staking = await get("Staking", signer);
		const ggp = await get("TokenGGP", signer);
		let tx = await ggp.approve(
			staking.address,
			ethers.utils.parseEther(amt.toString())
		);
		await tx.wait();
		tx = await staking.stakeGGP(ethers.utils.parseEther(amt.toString()));
		await tx.wait();
	});

task("staking:list", "List all stakers").setAction(async () => {
	const stakers = await getStakers();
	if (stakers.length > 0) logStakers(stakers);
});
