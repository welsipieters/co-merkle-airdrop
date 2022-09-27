import path from "path";
import fs from "fs";
import {Generator} from "./MerkleGenerator";

const allocationPath = path.join(__dirname, "../allocation.json");
const address = "0xFc05339D77df344fb4741D064c167fFfA4DFe21c";
const amount = 5000;

(() => {
    const configData = fs.readFileSync(allocationPath);
    const config = JSON.parse(configData.toString());

    const allocations: Record<string, number> = {};
    config.allocation.forEach((allocation: any) => {
        allocations[allocation.wallet] = allocation.total;
    });

    const addresses = Object.keys(allocations);

    let index = addresses.indexOf(address);
    let leaf = Generator.generateLeafNode(index, address, amount.toString());
    let proof = (new Generator(18, allocations)).tree.getHexProof(leaf);
    console.log(index, leaf, proof);
})();