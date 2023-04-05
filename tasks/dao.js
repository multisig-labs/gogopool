const { get, logtx } = require("./lib/utils.js");
const { ethers } = require("ethers");
const { task } = require("hardhat/config");

task("dao:set_ggavax_reserve", "Set ggAVAX reserve rate")
	.addParam(
		"reserve",
		"percent to keep in contract as reserve, format as ether"
	)
	.setAction(async ({ reserve }) => {
		const dao = await get("ProtocolDAO");
		const tx = await dao.setTargetggAVAXReserveRate(
			ethers.utils.parseEther(reserve)
		);
		await logtx(tx);
	});
