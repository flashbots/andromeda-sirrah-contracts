import { ethers } from "ethers";
import fs from 'fs';
import net from "net";
import fetch from "node-fetch";

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
  let ADDR_OVERRIDES: {[key: string]: any} = LocalConfig.ADDR_OVERRIDES;
  if (path in LocalConfig.ADDR_OVERRIDES) {
    const addr = ADDR_OVERRIDES[path];
    console.log("found address "+addr+" for "+path+", attaching it instead of deploying a new one");
    return new Promise((resolve) => {
      resolve([attach_artifact(path, signer, addr), true]);
    });
  }
  const contract = await deploy_artifact_direct(path, signer, ...args);

  ADDR_OVERRIDES[path] = contract.target;
  let updatedConfig = {
    ...LocalConfig,
    ADDR_OVERRIDES,
  };
  delete updatedConfig.default;

  fs.writeFileSync("deployment.json", JSON.stringify(updatedConfig, null, 2));

  return [contract, false];
}

/* Contract utils */
export async function derive_key(address: string, kettle: net.Socket | string, KM: ethers.Contract, index: number = 0) {
  const offchainDeriveTxData = await KM.offchain_DeriveKey.populateTransaction(address, index);
  let resp = await kettle_execute(kettle, offchainDeriveTxData.to, offchainDeriveTxData.data);

  let executionResult = JSON.parse(resp);
  if (executionResult.Success === undefined) {
    throw("execution did not succeed: "+JSON.stringify(resp));
  }

  const offchainDeriveResult = KM.interface.decodeFunctionResult(KM.offchain_DeriveKey.fragment, executionResult.Success.output.Call).toObject();
  const onchainDeriveTx = await (await KM.onchain_DeriveKey(address, offchainDeriveResult.dPub, offchainDeriveResult.sig, index)).wait();

  console.log("submitted derive key for "+address+" in "+onchainDeriveTx.hash);  
}


/* Kettle utils */
export function connect_kettle(conn: object | string): net.Socket | string {
  if (typeof conn === 'string') {
    return conn;
  }
  return net.connect(conn);
}
export async function kettle_advance(server: net.Socket | string): Promise<string> {
  let resp = await send_to_kettle(server, "advance");
  if (resp !== 'advanced') {
    throw("kettle did not advance, refusing to continue: "+resp);
  }
  return resp;
}
export async function kettle_execute(server: net.Socket | string, to: string, data: string): Promise<string> {
  const cmd = 'execute {"caller":"0x0000000000000000000000000000000000000000","gas_limit":21000000,"gas_price":"0x0","transact_to":{"Call":"'+to+'"},"value":"0x0","data":"'+data+'","nonce":0,"chain_id":null,"access_list":[],"gas_priority_fee":null,"blob_hashes":[],"max_fee_per_blob_gas":null}';
  return await send_to_kettle(server, cmd);
}

export async function send_to_kettle(server: net.Socket | string, cmd: string): Promise<string> {
  if (typeof server === 'string') {
      const response = await fetch(server, {
      method: 'POST',
      headers: {'Content-Type': 'text/plain'},
      body: cmd
    });

    return (await response.text()).trim().replace(/^"|"$/gm,'').replace(/\\"/gm,'"');
  }

  return new Promise((resolve) => {
    let outBuf = "";
    server.on('data', function(b) {
      outBuf += b.toString("utf-8");
      if (outBuf.endsWith("\n")) {
        resolve(outBuf.trim().replace(/^"|"$/gm,'').replace(/\\"/gm,'"'));
      }
    });
    server.write(cmd+"\n");
  });
}
