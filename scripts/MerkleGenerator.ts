import fs from "fs"; // Filesystem
import path from "path"; // Path
import keccak256 from "keccak256"; // Keccak256 hashing
import MerkleTree from "merkletreejs"; // MerkleTree.js
import {parseUnits, solidityKeccak256} from "ethers/lib/utils";


const allocationPath = path.join(__dirname, "../allocation.json");
const outputPath = path.join(__dirname, `../output/merkle-${String(Date.now())}.json`);

const throwAndExit = (error: string) => {
    console.error(error);
    process.exit(1);
}

export class Generator {
    recipients: {[address: string]: number} = {};
    tree: MerkleTree;

    constructor(allocation: Record<string, number>) {
        this.recipients = allocation;

        console.info("Generating Merkle tree.");

        const addresses = Object.keys(allocation);

        this.tree = new MerkleTree(
            addresses.map((address, index) => {
                return Generator.generateLeafNode(
                    index,
                    address,
                    parseUnits(allocation[address].toString(), process.env.decimals).toString()
                );
            }),
            keccak256,
            {sortPairs: true}
        );

        console.info(`Generated root: ${this.tree.getHexRoot()}`);

        fs.writeFileSync(
            outputPath,
            JSON.stringify({
                root: this.tree.getHexRoot()
            })
        );

        console.info(`Generated Merkle tree and root saved to ${outputPath}`)
    }

    static generateLeafNode(index: number, address: string, amount: string): Buffer {
        return Buffer.from(
            solidityKeccak256(["uint256", "address", "uint256"], [index, address, amount]).slice(2),
            "hex"
        );
    }
}

(async () => {
    if (!fs.existsSync(allocationPath)) {
        throwAndExit("Missing `allocation.json`.\r\nYou can add this file by running `cp allocation.json.dist allocation.json` in the root directory.");
    }

    const configData = fs.readFileSync(allocationPath);
    const config = JSON.parse(configData.toString());

    if (config === undefined) {
        throwAndExit("Corrupted `allocation.json` file.");
    }

    const allocations: Record<string, number> = {};
    config.forEach((allocation: any) => {
        allocations[allocation.wallet] = allocation.total_co;
    });

    new Generator(allocations);
})();