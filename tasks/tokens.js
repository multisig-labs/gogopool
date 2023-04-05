/* eslint-disable no-undef */
// hardhat ensures hre is always in scope, no need to require
const { task } = require("hardhat/config");
const { overrides, get, getNamedAccounts, logtx } = require("./lib/utils");

task("avax:deal")
	.addParam("addr", "", "")
	.addParam("recip", "", "")
	.addParam("amt", "", 0, types.int)
	.setAction(async ({ addr, recip, amt }) => {
		amt = ethers.utils.parseEther(amt.toString());
		if (addr == "") {
			addr = (await getNamedAccounts())[recip];
		}

		const deployer = (await getNamedAccounts()).deployer;
		const tx = await deployer.sendTransaction({
			to: addr,
			value: amt,
		});
		await logtx(tx);
	});

task("ggavax:sync_rewards", "")
	.addParam("actor", "Account used to send tx")
	.setAction(async ({ actor }) => {
		const signer = (await getNamedAccounts())[actor];
		const ggAVAX = await get("TokenggAVAX", signer);
		await ggAVAX.callStatic.syncRewards();
		tx = await ggAVAX.syncRewards();
		await logtx(tx);
	});

task("ggavax:liqstaker_deposit_avax")
	.addParam("actor", "")
	.addParam("amt", "", 0, types.int)
	.setAction(async ({ actor, amt }) => {
		const addr = (await getNamedAccounts())[actor];
		const ggAVAX = await get("TokenggAVAX", addr);
		tx = await ggAVAX.depositAVAX({
			...overrides,
			value: ethers.utils.parseEther(amt.toString()),
		});
		await logtx(tx);
	});

task("ggavax:liqstaker_redeem_ggavax")
	.addParam("actor", "")
	.addParam("amt", "", 0, types.int)
	.setAction(async ({ actor, amt }) => {
		const addr = (await getNamedAccounts())[actor];
		const ggAVAX = await get("TokenggAVAX", addr);
		const avaxAmt = await ggAVAX.previewRedeem(
			ethers.utils.parseEther(amt.toString())
		);
		console.log(`redeeming for ${ethers.utils.formatUnits(avaxAmt)} avax`);
		tx = await ggAVAX.redeemAVAX(
			ethers.utils.parseEther(amt.toString()),
			overrides
		);
		await logtx(tx);
	});

task("ggavax:available_for_staking", "AVAX available for staking").setAction(
	async () => {
		const ggAVAX = await get("TokenggAVAX");
		const amtAvailForStaking = await ggAVAX.amountAvailableForStaking();
		console.log(
			"amount available for staking",
			ethers.utils.formatUnits(amtAvailForStaking)
		);
	}
);

task("ggavax:total_assets", "Total assets in ggavax contract").setAction(
	async () => {
		const ggAVAX = await get("TokenggAVAX");
		const totalAssets = await ggAVAX.totalAssets();
		console.log("total assets", ethers.utils.formatUnits(totalAssets));
	}
);

task("ggavax:balance", "Balance of ggAVAX contract").setAction(async () => {
	const ggavax = await get("TokenggAVAX");
	const balAVAX = await hre.ethers.provider.getBalance(ggavax.address);
	console.log("ggavax contract balance", ethers.utils.formatUnits(balAVAX));
});

task("ggavax:preview_withdraw", "Preview shares -> assets && assets -> shares")
	.addParam("amt", "amount to preview", 0, types.int)
	.setAction(async ({ amt }) => {
		const ggAVAX = await get("TokenggAVAX");

		const redeemPreview = await ggAVAX.previewRedeem(
			ethers.utils.parseEther(amt.toString())
		);
		console.log("shares -> assets", ethers.utils.formatUnits(redeemPreview));

		const withdrawPreview = await ggAVAX.previewWithdraw(
			ethers.utils.parseEther(amt.toString())
		);
		console.log("assets -> shares", ethers.utils.formatUnits(withdrawPreview));
	});

task("wavax:balance", "Balance of WAVAX contract").setAction(async () => {
	const wavax = await get("WAVAX");
	const bal = await wavax.totalSupply();
	console.log("wavax balance", ethers.utils.formatUnits(bal));
});

task("ggp:deal")
	.addParam("recip", "", "")
	.addParam("addr", "", "")
	.addParam("amt", "", 0, types.int)
	.setAction(async ({ recip, amt, addr }) => {
		amt = ethers.utils.parseEther(amt.toString());
		if (addr == "") {
			addr = (await getNamedAccounts())[recip].address;
		}

		const ggp = await get("TokenGGP");
		let tx = await ggp.transfer(addr, amt);
		await logtx(tx);
	});

task("ggp:balance_of")
	.addParam("actor", "actor to check balance of", "")
	.addParam("addr", "addr to check balance of", "")
	.setAction(async ({ actor, addr }) => {
		if (actor !== "") {
			addr = (await getNamedAccounts())[actor].address;
		}
		const ggp = await get("TokenGGP");
		const bal = await ggp.balanceOf(addr);
		console.log("balance", ethers.utils.formatUnits(bal));
	});

task("ggp:allowance")
	.addParam("actor", "actor to check allowance of", "")
	.addParam("addr", "addr to check balance of", "")
	.addParam("spender", "contract doing the spending (defaults to Staking)", "")
	.setAction(async ({ actor, addr, spender }) => {
		if (actor !== "") {
			addr = (await getNamedAccounts())[actor].address;
		}
		if (spender === "") {
			spender = (await get("Staking")).address;
		}
		const ggp = await get("TokenGGP");
		const allowance = await ggp.allowance(addr, spender);
		console.log("allowance", ethers.utils.formatUnits(allowance));
	});

task("ggp:approve")
	.addParam("actor", "actor to allow")
	.addParam("contract", "address you want to authorize")
	.addParam("amt", "amount to approve", 0, types.int)
	.setAction(async ({ actor, contract, amt }) => {
		const a = (await getNamedAccounts())[actor];
		const c = await get(contract);
		const ggp = await get("TokenGGP", a);

		let tx = await ggp.approve(
			c.address,
			ethers.utils.parseEther(amt.toString())
		);
		await logtx(tx);
	});
