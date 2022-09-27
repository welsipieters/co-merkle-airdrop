import {ethers} from "hardhat";
import {Generator} from "../scripts/MerkleGenerator";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {expect} from "chai";
import {BigNumber, Contract, ContractFactory} from "ethers";
import {parseEther} from "ethers/lib/utils";
import {InfuraProvider} from "@ethersproject/providers";

describe("MerkleDistributor", () => {
    let deployUser: SignerWithAddress,
        testUser1: SignerWithAddress,
        testUser2: SignerWithAddress,
        distributorContract: ContractFactory,
        Distributor: Contract,
        erc20Contract: ContractFactory,
        Erc20: Contract,
        generator: Generator,
        allocation: {[address: string]: number},
        provider: InfuraProvider;

    before(async () => {
        [deployUser, testUser1, testUser2] = await ethers.getSigners();

        allocation = {};
        [testUser1, testUser2].forEach((signer) => {
            allocation[signer.address] = 100;
        })

        generator = new Generator(allocation);
        console.log("generator root", generator.tree.getHexRoot())

        erc20Contract = await ethers.getContractFactory('TestToken');
        Erc20 = await erc20Contract.connect(deployUser).deploy();

        distributorContract = await ethers.getContractFactory("MerkleDistributor");
        Distributor = await distributorContract.connect(deployUser).deploy();

        await Erc20.transfer(Distributor.address, parseEther("100000"))

        await deployUser.sendTransaction({
            to: Distributor.address,
            value: parseEther('100')
        })

        provider = new InfuraProvider(process.env.NETWORK, process.env.INFURA_API_KEY);
    });

    it('should be able to deposit', async () => {
        const beforeBalance = await Erc20.balanceOf(Distributor.address);
        await Erc20.connect(deployUser).approve(Distributor.address, parseEther("100000000"));
        await Distributor.connect(deployUser).deposit(Erc20.address, parseEther("100000"));
        const afterBalance = await Erc20.balanceOf(Distributor.address);

        expect(afterBalance).to.be.equal(parseEther("100000").add(beforeBalance));
    });

    it('should not be able to deposit from non-admin account', async () => {
        await Erc20.connect(deployUser).transfer(testUser1.address, parseEther("1000"));
        await Erc20.connect(testUser1).approve(Distributor.address, parseEther("100000000"));
        const tx = Distributor.connect(testUser1).deposit(Erc20.address, parseEther("100"));

        await expect(tx).to.be.reverted;
    });

    it('should be possible to create a campaign', async () => {
        const id = Distributor.campaignCount();
        const tx = await Distributor.connect(deployUser).createCampaign(
            Erc20.address,
            parseEther("10000"),
            1664232160,
            1764232160,
            generator.tree.getHexRoot()
        );

        await tx.wait();

        const campaign = await Distributor.campaigns(id);
        expect(campaign[1]).to.be.equal(Erc20.address);
    });

    it('should be possible to update a campaign', async () => {
        const id = Distributor.campaignCount();
        await Distributor.connect(deployUser).createCampaign(
            Erc20.address,
            parseEther("10000"),
            1664232160,
            1764232160,
            generator.tree.getHexRoot()
        );


        await Distributor.connect(deployUser).editCampaign(
            id,
            1664232160,
            1864232160,
            generator.tree.getHexRoot()
        )

        const campaign = await Distributor.campaigns(id);

        expect(campaign[4]).to.be.equal(1664232160);
        expect(campaign[5]).to.be.equal(1864232160);
    });

    // at this point im gonna stop testing ACL.

    it('should be possible to see if a user claimed already', async () => {
        expect(await Distributor.connect(testUser1).hasClaimed(0, 0)).to.be.false;
    });

    it('should be possible to claim', async () => {
        const leaf = Generator.generateLeafNode(0, testUser1.address, parseEther('100').toString());
        const proof = generator.tree.getHexProof(leaf);

        console.log(generator.tree.getHexRoot());
        const beforeBalance = await Erc20.balanceOf(testUser1.address);
        await Distributor.connect(testUser1).claim(0, 0, parseEther('100'), proof);
        const afterBalance = await Erc20.balanceOf(testUser1.address);

        expect(afterBalance).to.be.equal(beforeBalance.add(parseEther("100")));
        console.log("await Distributor.connect(testUser1).hasClaimed(0, 1)", await Distributor.connect(testUser1).hasClaimed(0, 0))
        expect(await Distributor.connect(testUser1).hasClaimed(0, 0)).to.be.true;
    });

    it('should not be possible to claim twice', async () => {
        const leaf = Generator.generateLeafNode(0, testUser1.address, parseEther('100').toString());
        const proof = generator.tree.getHexProof(leaf);

        const tx = Distributor.connect(testUser1).claim(0, 0, parseEther('100'), proof);

        await expect(tx).to.revertedWithCustomError(Distributor, "AlreadyClaimed");
    });

    it('should not be possible to claim an incorrect allocation', async () => {
        const leaf = Generator.generateLeafNode(1, testUser2.address, parseEther('1000').toString());
        const proof = generator.tree.getHexProof(leaf);

        const tx = Distributor.connect(testUser2).claim(0, 1, parseEther('1000'), proof);

        await expect(tx).to.revertedWithCustomError(Distributor, "IncorrectAllocation");
    });

    it('should be possible to withdraw ERC-20 tokens', async () => {
        const oldBalance = await Erc20.balanceOf(testUser1.address);
        await Distributor.connect(deployUser).withdrawErc20(Erc20.address, testUser1.address, parseEther('138'));
        const newBalance = await Erc20.balanceOf(testUser1.address);

        expect(newBalance).to.be.equal(oldBalance.add(parseEther('138')));
    });

    it('should be possible to withdraw ETH', async () => {
        const oldBalance = await ethers.provider.getBalance(testUser1.address);
        await Distributor.connect(deployUser).withdrawEth(testUser1.address, parseEther('1.213'));
        const newBalance = await ethers.provider.getBalance(testUser1.address);

        expect(newBalance).to.be.equal(oldBalance.add(parseEther('1.213')));
    });


});