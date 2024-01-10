import fs from 'fs';

import { ethers, JsonRpcProvider } from "ethers";

import { TCBInfoStruct, EnclaveIdStruct } from "lib/automata-dcap-v3-attestation/typechain-types/contracts/AutomataDcapV3Attestation";

import { deploy_artifact } from "./common.ts"

import * as LocalConfig from '../deployment.json'


async function deploy() {
  const provider = new JsonRpcProvider(LocalConfig.RPC_URL);
  const wallet = new ethers.Wallet(LocalConfig.PRIVATE_KEY, provider);

  const [SigVerifyLib, _] = await deploy_artifact(LocalConfig.SIGVERIFY_LIB_ARTIFACT, wallet);
  const [Andromeda, andomedaFound] = await deploy_artifact(LocalConfig.ANDROMEDA_ARTIFACT, wallet, SigVerifyLib.target);

  if (andomedaFound) { 
    console.log("Andromeda already deployed, not configuring it");
  } else {
    const enclaveId = JSON.parse(fs.readFileSync(LocalConfig.QE_IDENTITY_FILE, 'utf8')) as EnclaveIdStruct.EnclaveIdStruct;
    const enclaveIdTx = await (await Andromeda.configureQeIdentityJson(enclaveId)).wait();
    console.log("configured QeIdentidy in "+enclaveIdTx.hash);

    /* Done as a separate step, maybe we should omit this */
    const tcbInfo = JSON.parse(fs.readFileSync(LocalConfig.TCB_INFO_FILE, 'utf8')) as TCBInfoStruct.TCBInfoStruct.tcbInfo;
    const tcbInfoTx = await (await Andromeda.configureTcbInfoJson(tcbInfo.fmspc, tcbInfo)).wait();
    console.log("configured tcbInfo in "+tcbInfoTx.hash);
  }

  const KeyManagerSN = await deploy_artifact(LocalConfig.KEY_MANAGER_SN_ARTIFACT, wallet, Andromeda.target);
}

deploy().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
