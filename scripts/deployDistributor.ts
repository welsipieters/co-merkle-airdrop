const hre = require("hardhat");
const { ethers } = hre;

(async () => {
    const Distributor = await ethers.getContractFactory('MerkleDistributor');
    const distributor = await Distributor.deploy();

    await distributor.deployed();

    console.log("distributor deployed to: ", distributor.address);
})().catch(e => {
    console.log(e)
    process.exit(1);
})