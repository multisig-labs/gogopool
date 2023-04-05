/* eslint-disable no-undef */
// hardhat ensures hre is always in scope, no need to require
const { ethers, utils } = require("ethers");
const { task } = require("hardhat/config");
const {
	get,
	log,
	logtx,
	getNamedAccounts,
	getStakers,
} = require("./lib/utils");

task(
	"nopClaim:distributeRewards",
	"Calculate and distribute rewards to the node operators"
).setAction(async () => {
	const rialto = (await getNamedAccounts()).rialto1;
	const nopClaim = await get("ClaimNodeOp", rialto);
	const stakers = await getStakers();

	eligibleStakers = [];
	let totalEligibleGGPStaked = ethers.BigNumber.from("0");
	for (staker of stakers) {
		const isEligible = await nopClaim.isEligible(staker.stakerAddr);
		log(`Eligible ${staker.stakerAddr} ${isEligible}`);
		if (isEligible) {
			// TODO: get their effective stake not their total staked
			// add their ggp staked to the total ggp staked
			totalEligibleGGPStaked = totalEligibleGGPStaked.add(staker.ggpStaked);
			// add them to the eligible stakers
			eligibleStakers.push(staker.stakerAddr);
		}
	}

	for (staker of eligibleStakers) {
		const tx = await nopClaim.calculateAndDistributeRewards(
			staker,
			totalEligibleGGPStaked
		);
		logtx(tx);
	}
});

task("nopClaim:isEligible", "is a staker eligible")
	.addParam("staker", "Account used to send tx")
	.setAction(async ({ staker }) => {
		const signer = (await getNamedAccounts())[staker];
		const nopClaim = await get("ClaimNodeOp");
		const staking = await get("Staking");
		log(signer.address);
		const index = await staking.getIndexOf(signer.address);
		const user = await staking.getStaker(index);
		log(
			utils.formatEther(
				`${await staking.getCollateralizationRatio(user.stakerAddr)}`
			)
		);
		const isEligible = await nopClaim.isEligible(user.stakerAddr);
		log(`Is ${staker} eligible for rewards?: ${isEligible}`);
	});

task("staking:getMinipoolCount", "get minipool count for actor")
	.addParam("actor")
	.setAction(async ({ actor }) => {
		const a = (await getNamedAccounts())[actor];
		const staking = await get("Staking");

		const count = await staking.getMinipoolCount(a.address);
		console.log("minipool count", count);
	});

task("staking:getGGPRewards")
	.addParam("actor")
	.setAction(async ({ actor }) => {
		const a = (await getNamedAccounts())[actor];
		const staking = await get("Staking");
		const nop = await get("ClaimNodeOp", a);
		const preview = await nop.previewClaimAmount();
		console.log("preview amount", preview);
		const rewardsAmount = await staking.getGGPRewards(a.address);
		console.log("rewards amount", utils.formatEther(rewardsAmount));
	});

task("staking:claimAndRestake")
	.addParam("actor")
	.addParam("amt", "test", "amount to claim")
	.setAction(async ({ actor, rewards }) => {
		const a = (await getNamedAccounts())[actor];
		const nopClaim = await get("ClaimNodeOp", a);
		tx = await await nopClaim.claimAndRestake(utils.parseEther(rewards));
		logtx(tx);
	});

task("nopClaim:claimAndRestakeHalf", "claim rewards for the given user")
	.addParam("actor", "Account used to send tx")
	.setAction(async ({ actor }) => {
		const signer = (await getNamedAccounts())[actor];
		const nopClaim = await get("ClaimNodeOp", signer);
		const staking = await get("Staking", signer);
		const rewardAmt = utils.formatEther(
			`${await staking.getGGPRewards(signer.address)}`
		);
		const halfRewardAmt = rewardAmt / 2;
		log(
			`${actor} has ${rewardAmt} in GGP rewards they can claim. Claiming half (${halfRewardAmt}) and restaking the other half`
		);
		try {
			tx = await nopClaim.claimAndRestake(utils.parseEther(`${halfRewardAmt}`));
			// tx = await staking.decreaseGGPRewards(
			// 	signer.address,
			// 	utils.parseEther(`${rewardAmt}`)
			// );
			logtx(tx);
		} catch (error) {
			log(error.reason);
		}
		const rewardAmtAfterClaim = utils.formatEther(
			`${await staking.getGGPRewards(signer.address)}`
		);
		log(
			`${actor} has claimed GGP rewards they now have ${rewardAmtAfterClaim} in GGP rewards`
		);
		const newGGPStaked = utils.formatEther(
			`${await staking.getGGPStake(signer.address)}`
		);
		log(`${actor} now has ${newGGPStaked} in GGP staked`);
	});
