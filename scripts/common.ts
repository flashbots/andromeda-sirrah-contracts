import { ethers } from "ethers";
import fs from 'fs';
import net from "net";

import * as LocalConfig from '../deployment.json';

/* Utility functions */

export function attach_artifact(path: string, signer: ethers.Signer, address: string): ethers.Contract {
  const factory = ethers.ContractFactory.fromSolidity(fs.readFileSync(path, "utf-8"), signer);
  return factory.attach(address);
}

export async function deploy_artifact(path: string, signer: ethers.Signer, ...args: any[]): Promise<[ethers.Contract, boolean]> {
  if (path in LocalConfig.ADDR_OVERRIDES) {
    const addr = LocalConfig.ADDR_OVERRIDES[path];
    console.log("found address "+addr+" for "+path+", attaching it instead of deploying a new one");
    return new Promise((resolve) => {
      resolve([attach_artifact(path, signer, addr), true]);
    });
  }

  const factory = ethers.ContractFactory.fromSolidity(fs.readFileSync(path, "utf-8"), signer);
  const contract = await (await factory.deploy(...args)).waitForDeployment();
  console.log("Deployed `"+path+"` to "+contract.target);

  LocalConfig.ADDR_OVERRIDES[path] = contract.target;

  fs.writeFileSync("deployment.json", JSON.stringify(LocalConfig.default, null, 2));

  return [contract, false];
}

/* Utils */
export async function sendToKettle(s: net.Socket, cmd: string): Promise<string> {
  return new Promise((resolve) => {
    let outBuf = "";
    s.on('data', function(b) {
      outBuf += b.toString("utf-8");
      if (outBuf.endsWith("\n")) {
        resolve(outBuf.trim().replace(/^"|"$/gm,'').replace(/\\"/gm,'"'));
      }
    });
    s.write(cmd+"\n");
  });
}