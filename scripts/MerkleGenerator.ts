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

    constructor(decimals: number, allocation: Record<string, number>) {
        Object.entries(allocation).map(([address, tokens]) => {
            this.recipients[address] = tokens;
        });

        console.info("Generating Merkle tree.");

        const addresses = Object.keys(allocation);
        addresses.sort(function(a, b) {
            const al = a.toLowerCase(), bl = b.toLowerCase();
            if (al < bl) { return -1; }
            if (al > bl) { return 1; }
            return 0;
        });

        this.tree = new MerkleTree(
            addresses.map((address, index) => {
                return Generator.generateLeafNode(
                    index,
                    address,
                    parseUnits(allocation[address].toString(), decimals.toString()).toString()
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

    if (config.allocation == undefined || config.token_decimals == undefined) {
        throwAndExit("Corrupted `allocation.json` file.");
    }

    const decimals: number = config.token_decimals;
    const allocation: Record<string, number> = config.allocation;

    new Generator(decimals, allocation);
})();