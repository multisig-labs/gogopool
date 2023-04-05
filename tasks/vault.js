/* eslint-disable no-undef */
// hardhat ensures hre is always in scope, no need to require
const { addrs, get, log, logf } = require("./lib/utils");
const { getNamedAccounts, logtx } = require("./lib/utils");

task("vault:list", "List contract balances").setAction(async () => {
	const vault = await get("Vault");
	log("=== VAULT BALANCES FOR CONTRACT NAMES ===");
	logf("%-20s %-10s %-10s %-10s", "Contract", "AVAX", "WAVAX", "GGP");
	for (const name in addrs) {
		const balAVAX = await vault.balanceOf(name);
		const balWAVAX = await vault.balanceOfToken(name, addrs.WAVAX);
		const balGGP = await vault.balanceOfToken(name, addrs.TokenGGP);
		logf(
			"%-20s %-10d %-10s %-10s",
			name,
			hre.ethers.utils.formatUnits(balAVAX),
			hre.ethers.utils.formatUnits(balWAVAX),
			hre.ethers.utils.formatUnits(balGGP)
		);
	}
	log("=== ggAVAX CONTRACT BALANCES ===");
	const wavax = await get("WAVAX");
	const balWAVAX = await wavax.balanceOf(addrs.TokenggAVAX);
	logf("%-20s %-10s", "WAVAX", hre.ethers.utils.formatUnits(balWAVAX));
});

task("vault:deposit_token", "deposit a token from to vault")
	.addParam("actor")
	.addParam("contract")
	.addParam("amt", "", 0, types.int)
	.setAction(async ({ actor, contract, amt }) => {
		const signer = (await getNamedAccounts())[actor];

		const vault = await get("Vault", signer);
		const ggp = await get("TokenGGP", signer);
		amt = ethers.utils.parseEther(amt.toString());

		let tx = await ggp.approve(vault.address, amt);
		await logtx(tx);

		tx = await vault.depositToken("ClaimNodeOp", ggp.address, amt);
		await logtx(tx);
	});

task(
	"vault:register_allowed_tokens",
	"register ggp token to be accepted"
).setAction(async () => {
	const signer = (await getNamedAccounts())["deployer"];

	const vault = await get("Vault", signer);
	const ggp = await get("TokenGGP", signer);

	const tx = await vault.addAllowedToken(ggp.address);
	await logtx(tx);
	log(ggp.address);
});
