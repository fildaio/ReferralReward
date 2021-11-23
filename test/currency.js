const { default: BigNumber } = require("bignumber.js");

const ChannelManager = artifacts.require("ChannelManager");
const Channel = artifacts.require("Channel");

const channelName = "test.com";

// heco测试
// const fUSDT = "0xAab0C9561D5703e84867670Ac78f6b5b4b40A7c1"; // 主网
// const fUSDT = "0x9f76E988eE3a0d5F13c9bd693F72CF8c203E3b9c"; // 测试网
// const USDT = "0xa71edc38d189767582c38a3145b5873052c3e47a"; // 主网
// const USDT = "0x04F535663110A392A6504839BEeD34E019FdB4E0"; // 测试网
// const nativeToken="0x5545153ccfca01fbd7dd11c0b23ba694d9509a6f"; // 主网
// const nativeToken = "0x0000000000000000000000000000000000000000"; // 测试网
// const maximillionToken="0x32fbB9c822ABd1fD9e4655bfA55A45285Fb8992d"; // 主网
// const maximillionToken = "0x32fbB9c822ABd1fD9e4655bfA55A45285Fb8992d"; // 测试网

// bsc测试
const fUSDT = "0x26bCC2f4ff24e321542505b23e721870Bb1F36CF"; // 测试网
const USDT = "0x337610d27c682E347C9cD60BD4b3b107C9d34dDd"; // 测试网
const nativeToken = "0x0000000000000000000000000000000000000000"; // 测试网
const fNativeToken = "0xa557859AD20ccEeE646469baccC37b22caC1299a"
const maximillionToken = "0x80066F46552a8DeF13249FFF82085b4B6B748F59"; // 测试网

const ERC20ABI = require("./ERC20.json");
const share = 123;
const denomination = 10000;
const allowance = "123456789000000000";
const depositAmount = "1000000";
const borrowAmount = "500000";

let cm = null;
let c = null;
let channelAddress = "";
let agent = "";

contract("All Contracts", async accounts => {
	const getCM = async () => {
		if (!cm) {
			cm = await ChannelManager.deployed();
		}
	};

	const getC = async () => {
		if (!c) {
			c = await Channel.at(channelAddress);
		}
	};

	it("ChannelManager.createChannel()", async () => {
		await getCM();
		await cm.setWrappedNativeToken(fNativeToken);
		await cm.setMaximillion(maximillionToken);
		await cm.createChannel(channelName);

		channelAddress = await cm.channels(channelName);
		const nameResult = await cm.channelNames(channelAddress);
		assert.ok(nameResult === channelName, "wrong channel name or address.");
	});

	it("ChannelManager.assignManagerForChannel()", async () => {
		await getCM();
		await cm.assignManagerForChannel(channelAddress, accounts[0]);

		await getC();
		const adminResult = await c.hasRole(web3.utils.keccak256("ADMIN"), accounts[0]);
		assert.ok(adminResult, "failed to set ADMIN as accounts[0]");
	});

	it("ChannelManager.setShareRateOfChannel()", async () => {
		await getCM();
		await cm.setShareRateOfChannel(channelAddress, fNativeToken, share);

		const shareResult = await cm.getShareRateOfChannel(channelAddress, fNativeToken);
		assert.ok(new BigNumber(shareResult).eq(share), "wrong share rate.");
	});

	it("Channel.applyAgent()", async () => {
		await getC();
		await c.applyAgent();

		agent = await c.agent(accounts[0]);
		assert.ok(agent != "0x0000000000000000000000000000000000000000", agent);
	});

	it("Channel.filda()", async () => {
		await getC();
		const result = await c.filda();
		assert.ok(result === ChannelManager.address, result);
	});

	it("Channel.getShareRate()", async () => {
		await getC();
		const result = await c.getShareRate(fNativeToken);
		const shareResult = new BigNumber(result[0]);
		assert.ok(shareResult.eq(share), shareResult.toFixed());
	});

	it("Channel.deposit() - 本金分成模式 - 本币", async () => {
		await getC();
		await c.deposit(fNativeToken, depositAmount, {
			from: accounts[0],
			value: depositAmount
		});

		await getCM();
		const result = await cm.accShareByChannel(channelAddress);
		assert.ok(result[0][0] === nativeToken && new BigNumber(depositAmount).multipliedBy(share).dividedBy(denomination).eq(result[0][1]), "wrong share...")
	});

	it("Channel.borrow() - 本金分成模式 - 本币", async () => {
		await getC();
		await c.borrow(fNativeToken, borrowAmount);
	});

	it("Channel.repay() - 本金分成模式 - 本币", async () => {
		await getC();
		await c.repay(fNativeToken, borrowAmount, {
			from: accounts[0],
			value: borrowAmount
		});
	});

	it("Channel.userWithdraw() - 本金分成模式 - 本币", async () => {
		await getC();
		await c.userWithdraw(fNativeToken, new BigNumber(depositAmount).multipliedBy(1 - share / denomination).multipliedBy(0.99).toFixed());

		const balance = await web3.eth.getBalance(agent);
		assert.ok(new BigNumber(balance).lte(new BigNumber(depositAmount).multipliedBy(share / denomination).multipliedBy(0.01)), balance);
	});

	it("Channel.withdraw() - 本金分成模式 - 本币", async () => {
		await getC();
		await c.withdraw();
	});

	it("ChannelManager.setChannelMode() - 记账模式 - 本币", async () => {
		await getCM();
		await cm.setChannelMode(channelAddress, 1);

		await getC();
		const result = await c.getMode();
		assert.ok(new BigNumber(result).eq(1), "wrong mode.");
	});

	it("Channel.deposit() - 记账模式 - 本币", async () => {
		await getC();
		await c.deposit(fNativeToken, depositAmount, {
			from: accounts[0],
			value: depositAmount
		});

		await getCM();
		const result = await cm.accAmountByChannel(channelAddress);
		assert.ok(result[0][0] === fNativeToken && new BigNumber(depositAmount).eq(result[0][1]), "wrong amount...");
	});

	it("Channel.borrow() - 记账模式 - 本币", async () => {
		await getC();
		await c.borrow(fNativeToken, borrowAmount);
	});

	it("Channel.repay() - 记账模式 - 本币", async () => {
		await getC();
		await c.repay(fNativeToken, borrowAmount, {
			from: accounts[0],
			value: borrowAmount
		});
	});

	it("Channel.userWithdraw() - 记账模式 - 本币", async () => {
		await getC();
		await c.userWithdraw(fNativeToken, new BigNumber(depositAmount).multipliedBy(1 - share / denomination).multipliedBy(0.99).toFixed());

		const balance = await web3.eth.getBalance(agent);
		assert.ok(new BigNumber(balance).lte(new BigNumber(depositAmount).multipliedBy(0.01)), balance);
	});

	it("ChannelManager.cleanAccAmountByChannel() - 记账模式 - 本币", async () => {
		await getCM();
		await cm.cleanAccAmountByChannel(channelAddress);
	});
});