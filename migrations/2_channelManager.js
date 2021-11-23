const ChannelManager = artifacts.require("ChannelManager");

module.exports = async function (deployer, network, accounts) {
	await deployer.deploy(ChannelManager);
	await ChannelManager.deployed()
};
