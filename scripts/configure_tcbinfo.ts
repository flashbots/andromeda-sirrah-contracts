import fs from 'fs';
import { ethers, JsonRpcProvider } from "ethers";

import { TCBInfoStruct } from "lib/automata-dcap-v3-attestation/typechain-types/contracts/AutomataDcapV3Attestation";

import { attach_artifact } from "./common.ts"

import * as LocalConfig from '../deployment.json'

async function main() {
  const tcbInfoFiles = (process.env.TCB_INFO_FILES ?? '').trim().split(" ");
  
  if (tcbInfoFiles.length === 0) {
    throw new Error("TCB_INFO_FILES environment variable is not defined.");
  }

  const provider = new JsonRpcProvider(LocalConfig.RPC_URL);
  const wallet = new ethers.Wallet(LocalConfig.PRIVATE_KEY, provider);

  const Andromeda = await attach_artifact(LocalConfig.ANDROMEDA_ARTIFACT, wallet, LocalConfig.ADDR_OVERRIDES[LocalConfig.ANDROMEDA_ARTIFACT]);

  for (const tcbInfoFile in tcbInfoFiles) {
    const tcbInfo = JSON.parse(fs.readFileSync(tcbInfoFiles[tcbInfoFile], 'utf8')) as TCBInfoStruct.TCBInfoStruct.tcbInfo;
    const isAlreadyDeployed = (await Andromeda.tcbInfo(tcbInfo.fmspc))[1] === tcbInfo.fmspc;
    if (!isAlreadyDeployed) {
      const tcbInfoTx = await (await Andromeda.configureTcbInfoJson(tcbInfo.fmspc, tcbInfo)).wait();
      console.log("configured "+tcbInfo.fmspc+" in "+tcbInfoTx.hash);
    } else {
      console.log(tcbInfo.fmspc+" already configured");
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
