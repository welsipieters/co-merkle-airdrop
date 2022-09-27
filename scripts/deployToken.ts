import {ethers} from "hardhat";

(async () => {
    const Token = await ethers.getContractFactory('TestToken');
    const token = await Token.deploy();

    await token.deployed();

    console.log("testToken deployed to: ", token.address);
})().catch(e => {
    console.log(e)
    process.exit(1);
})