import { ethers } from "ethers";
import fs from 'fs';

export const LocalConfig = {
	RPC_URL: "https://rpc.rigil.suave.flashbots.net",
	PRIVATE_KEY: process.env.RAW_PRIVATE_KEY, // Make sure to `export RAW_PRIVATE_KEY=...`
	TCB_INFO_FILE: "lib/automata-dcap-v3-attestation/contracts/assets/tcbInfo2.json",
	QE_IDENTITY_FILE: "lib/automata-dcap-v3-attestation/contracts/assets/identity.json",

	SIGVERIFY_LIB_ARTIFACT: "out/SigVerifyLib.sol/SigVerifyLib.json",
	ANDROMEDA_ARTIFACT: "out/Andromeda.sol/Andromeda.json",
	KEY_MANAGER_SN_ARTIFACT: "out/KeyManager.sol/KeyManager_v0.json",
}

export const ADDR_OVERRIDES: { [path: string]: string } = {};
ADDR_OVERRIDES[LocalConfig.SIGVERIFY_LIB_ARTIFACT] = "0xf933Cee2EDE6206868837A574eccd495592b41cF";
ADDR_OVERRIDES[LocalConfig.ANDROMEDA_ARTIFACT] = "0x48C8f637BF0aeBF0CD45bCbEC1797cA1c331A3Da";
ADDR_OVERRIDES[LocalConfig.KEY_MANAGER_SN_ARTIFACT] = "0x489602F9f2b13729a6D53238B5a9E91d77111F0c";

/* Utility functions */

export function attach_artifact(path: string, signer: ethers.Signer, address: string): ethers.Contract {
  const factory = ethers.ContractFactory.fromSolidity(fs.readFileSync(path, "utf-8"), signer);
  return factory.attach(address);
}

export async function deploy_artifact(path: string, signer: ethers.Signer, ...args: any[]): Promise<ethers.Contract> {
  if (path in ADDR_OVERRIDES) {
    const addr = ADDR_OVERRIDES[path];
    console.log("found address "+addr+" for "+path+", attaching it instead of deploying a new one");
    return new Promise((resolve) => {
      resolve(attach_artifact(path, signer, addr));
    });
  }

  const factory = ethers.ContractFactory.fromSolidity(fs.readFileSync(path, "utf-8"), signer);
  const contract = await (await factory.deploy(...args)).waitForDeployment();
  console.log("Deployed `"+path+"` to "+contract.target);

  return contract;
}

