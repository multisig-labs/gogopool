/* eslint-disable no-undef */
// hardhat ensures hre is always in scope, no need to require
const {
	get,
	overrides,
	log,
	logf,
	getNamedAccounts,
	logtx,
} = require("./lib/utils");

const MAX_ENTRIES = 10;

task("multisig:list", "List all registered multisigs").setAction(async () => {
	const multisigManager = await get("MultisigManager");
	logf("%-42s %-10s %-10s", "Multisig", "Enabled", "C-Chain AVAX Balance");
	for (let i = 0; i < MAX_ENTRIES; i++) {
		try {
			const { addr, enabled } = await multisigManager.getMultisig(i);
			if (addr === hre.ethers.constants.AddressZero) break;
			const bal = await hre.ethers.provider.getBalance(addr);
			logf(
				"%-42s %-10s %-10.4d",
				addr,
				enabled,
				hre.ethers.utils.formatUnits(bal)
			);
		} catch (e) {
			log("error", e);
		}
	}
});

task("multisig:getNextActive", "Get next active multisig").setAction(
	async () => {
		const multisigManager = await get("MultisigManager");
		const addr = await multisigManager.getNextActiveMultisig();
		log(addr);
	}
);

task("multisig:register", "Register and enable a multisig address")
	.addParam("name", "Named account", "")
	.addParam("addr", "Address", "")
	.setAction(async ({ addr, name }) => {
		if (addr === "") {
			addr = (await getNamedAccounts())[name].address;
		}
		const multisigManager = await get("MultisigManager");
		try {
			const tx = await multisigManager.registerMultisig(addr, overrides);
			await logtx(tx);
		} catch (e) {
			log(`Error: ${e}`);
		}
		try {
			const tx = await multisigManager.enableMultisig(addr, overrides);
			await logtx(tx);
		} catch (e) {
			log(`Error: ${e}`);
		}
		// const ms = await multisigManager.getNextActiveMultisig();
		log(`Multisig Registered: ${addr}`);
	});

task("multisig:disable", "disable a multisig address")
	.addParam("name", "Named account", "")
	.addParam("addr", "Address", "")
	.setAction(async ({ addr, name }) => {
		if (addr === "") {
			addr = (await getNamedAccounts())[name].address;
		}
		const multisigManager = await get("MultisigManager");
		try {
			const tx = await multisigManager.disableMultisig(addr, overrides);
			await logtx(tx);
		} catch (e) {
			log(`Error: ${e}`);
		}
		log(`Multisig Disabled: ${addr}`);
	});

task("multisig:enable", "enable a multisig address")
	.addParam("name", "Named account", "")
	.addParam("addr", "Address", "")
	.setAction(async ({ addr, name }) => {
		if (addr === "") {
			addr = (await getNamedAccounts())[name].address;
		}
		const multisigManager = await get("MultisigManager");
		try {
			const tx = await multisigManager.enableMultisig(addr, overrides);
			await logtx(tx);
		} catch (e) {
			log(`Error: ${e}`);
		}
		log(`Multisig Enabled: ${addr}`);
	});
