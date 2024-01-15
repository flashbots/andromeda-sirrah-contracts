import { ethers } from "ethers";
import fs from 'fs';
import net from "net";

import * as LocalConfig from '../deployment.json';

/* Utility functions */

export function attach_artifact(path: string, signer: ethers.Signer, address: string): ethers.Contract {
  const factory = ethers.ContractFactory.fromSolidity(fs.readFileSync(path, "utf-8"), signer);
  return factory.attach(address);
}

export async function deploy_artifact_direct(path: string, signer: ethers.Signer, ...args: any[]): Promise<ethers.Contract> {
  const factory = ethers.ContractFactory.fromSolidity(fs.readFileSync(path, "utf-8"), signer);
  const contract = await (await factory.deploy(...args)).waitForDeployment();
  console.log("Deployed `"+path+"` to "+contract.target);

  return contract;
}

export async function deploy_artifact(path: string, signer: ethers.Signer, ...args: any[]): Promise<[ethers.Contract, boolean]> {
  if (path in LocalConfig.ADDR_OVERRIDES) {
    const addr = LocalConfig.ADDR_OVERRIDES[path];
    console.log("found address "+addr+" for "+path+", attaching it instead of deploying a new one");
    return new Promise((resolve) => {
      resolve([attach_artifact(path, signer, addr), true]);
    });
  }
  const contract = await deploy_artifact_direct(path, signer, ...args);

  LocalConfig.ADDR_OVERRIDES[path] = contract.target;

  fs.writeFileSync("deployment.json", JSON.stringify(LocalConfig.default, null, 2));

  return [contract, false];
}

/* Utils */
export async function kettle_advance(s: net.Socket): Promise<string> {
  return await send_to_kettle(s, "advance");
}
export async function kettle_execute(s: net.Socket, to: string, data: string): Promise<string> {
  const cmd = 'execute {"caller":"0x0000000000000000000000000000000000000000","gas_limit":21000000,"gas_price":"0x0","transact_to":{"Call":"'+to+'"},"value":"0x0","data":"'+data+'","nonce":0,"chain_id":null,"access_list":[],"gas_priority_fee":null,"blob_hashes":[],"max_fee_per_blob_gas":null}';
  return await send_to_kettle(s, cmd);
}

export async function send_to_kettle(s: net.Socket, cmd: string): Promise<string> {
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