import { ethers } from "ethers";

import fs from 'fs';

import { exec } from "child_process";
import { promisify } from "util";
const async_exec = promisify(exec);

import { TCBInfoStruct, EnclaveIdStruct } from "lib/automata-dcap-v3-attestation/typechain-types/contracts/AutomataDcapV3Attestation";

const RPC_URL = "https://rpc.rigil.suave.flashbots.net";
const PRIVATE_KEY = process.env.RAW_PRIVATE_KEY // Make sure to `export RAW_PRIVATE_KEY=...`
const TCB_INFO_FILE = "lib/automata-dcap-v3-attestation/contracts/assets/tcbInfo2.json";
const QE_IDENTITY_FILE = "lib/automata-dcap-v3-attestation/contracts/assets/identity.json";

const SIGVERIFY_LIB_ARTIFACT = "out/SigVerifyLib.sol/SigVerifyLib.json";
const ANDROMEDA_ARTIFACT = "out/Andromeda.sol/Andromeda.json";
const KEY_MANAGER_SN_ARTIFACT = "out/KeyManager.sol/KeyManager_v0.json";

/* CHANGEME */
const ADDR_OVERRIDES: { [path: string]: string } = {};
ADDR_OVERRIDES[SIGVERIFY_LIB_ARTIFACT] = "0xf933Cee2EDE6206868837A574eccd495592b41cF";
ADDR_OVERRIDES[ANDROMEDA_ARTIFACT] = "0x48C8f637BF0aeBF0CD45bCbEC1797cA1c331A3Da";
ADDR_OVERRIDES[KEY_MANAGER_SN_ARTIFACT] = "0x489602F9f2b13729a6D53238B5a9E91d77111F0c";

async function deploy() {
  const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

  const SigVerifyLib = await deploy_artifact(SIGVERIFY_LIB_ARTIFACT, wallet);
  const Andromeda = await deploy_artifact(ANDROMEDA_ARTIFACT, wallet, SigVerifyLib.address);

  if (ANDROMEDA_ARTIFACT in ADDR_OVERRIDES) { 
    console.log("Andromeda already deployed, not configuring it");
  } else {
    const enclaveId = JSON.parse(fs.readFileSync(QE_IDENTITY_FILE, 'utf8')) as EnclaveIdStruct.EnclaveIdStruct;
    const enclaveIdTx = await (await Andromeda.configureQeIdentityJson(enclaveId)).wait();
    console.log("configured QeIdentidy in "+enclaveIdTx.transactionHash);

    const tcbInfo = JSON.parse(fs.readFileSync(TCB_INFO_FILE, 'utf8')) as TCBInfoStruct.TCBInfoStruct.tcbInfo;
    const tcbInfoTx = await (await Andromeda.configureTcbInfoJson(tcbInfo.fmspc, tcbInfo)).wait();
    console.log("configured tcbInfo in "+tcbInfoTx.transactionHash);
  }

  const KeyManagerSN = await deploy_artifact(KEY_MANAGER_SN_ARTIFACT, wallet, Andromeda.address);
}

deploy().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});


/* Utils */

function attach_artifact(path: string, signer: ethers.signer, address: string): ethers.Contract {
  const factory = ethers.ContractFactory.fromSolidity(fs.readFileSync(path, "utf-8"), signer);
  return factory.attach(address);
}

async function deploy_artifact(path: string, signer: ethers.signer, ...args): Promise<ethers.Contract> {
  if (path in ADDR_OVERRIDES) {
    const addr = ADDR_OVERRIDES[path];
    console.log("found address "+addr+" for "+path+", attaching it instead of deploying a new one");
    return new Promise((resolve) => {
      resolve(attach_artifact(path, signer, addr));
    });
  }

  const factory = ethers.ContractFactory.fromSolidity(fs.readFileSync(path, "utf-8"), signer);

  const contract = await factory.deploy(...args);
  const tx = await contract.deployTransaction.wait();

  if (tx.status != 1) {
    throw("deploying "+path+" was not successful (reverted)");
  }

  console.log("deployed `"+path+"` to "+contract.address+" in tx "+tx.transactionHash);

  return contract;
}
