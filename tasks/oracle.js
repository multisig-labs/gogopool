/* eslint-disable no-undef */
// hardhat ensures hre is always in scope, no need to require
const { get, log, parseDelta, getNamedAccounts } = require("./lib/utils");

task("oracle:set_oneinch", "")
	.addParam("addr", "Address of One Inch price aggregator contract")
	.setAction(async ({ addr }) => {
		log(`OneInch addr: ${addr}`);
		const oracle = await get("Oracle");
		await oracle.setOneInch(addr);
	});

task("oracle:get_ggp_price_oneinch", "").setAction(async () => {
	const oracle = await get("Oracle");
	const result = await oracle.getGGPPriceInAVAXFromOneInch();
	log(
		`OneInch GGP Price: ${ethers.utils.formatEther(result.price)} @ ts ${
			result.timestamp
		}`
	);
});

task("oracle:set_ggp_price_oneinch", "Set the mocked oneinch price of GGP")
	.addParam("price", "price of GGP in AVAX")
	.setAction(async ({ price }) => {
		const priceParsed = ethers.utils.parseEther(price, "ether");
		const mock = await get("OneInchMock");
		await mock.setMockedRate(priceParsed);
		log(`GGP one inch reported price set to ${priceParsed}`);
	});

task("oracle:set_ggp", "")
	.addParam("actor", "Only a registered multisig can set the price")
	.addParam("price", "price of GGP in AVAX")
	.addParam("timestamp", "timestamp", 0, types.int)
	.addParam("interval", "i.e. 4h from last timestamp", "")
	.setAction(async ({ price, actor, timestamp, interval }) => {
		log(`GGP Price set to ${price} AVAX`);
		const priceParsed = ethers.utils.parseEther(price, "ether");
		const signer = (await getNamedAccounts())[actor];
		const oracle = await get("Oracle", signer);
		if (timestamp === 0 && interval === "") {
			// init price
			await oracle.setGGPPriceInAVAX(priceParsed, 0);
			return;
		}

		if (timestamp === 0) {
			const results = await oracle.getGGPPriceInAVAX();
			const lastTimestamp = results.timestamp;
			timestamp = lastTimestamp + parseDelta(interval);
		}
		await oracle.setGGPPriceInAVAX(priceParsed, timestamp);
	});

task("oracle:get_ggp", "").setAction(async () => {
	const oracle = await get("Oracle");
	const results = await oracle.getGGPPriceInAVAX();
	log(
		`GGP Price: ${ethers.utils.formatEther(results.price)} Timestamp: ${
			results.timestamp
		}`
	);
});
