import fs from 'fs';
import { ethers, JsonRpcProvider } from "ethers";

import { TCBInfoStruct } from "lib/automata-dcap-v3-attestation/typechain-types/contracts/AutomataDcapV3Attestation";

import { attach_artifact } from "./common.ts"

import * as LocalConfig from '../deployment.json'

async function main() {
  const tcbInfoFolder = process.env.TCB_INFO_FOLDER.trim();

  const provider = new JsonRpcProvider(LocalConfig.RPC_URL);
  const wallet = new ethers.Wallet(LocalConfig.PRIVATE_KEY, provider);

  const Andromeda = await attach_artifact(LocalConfig.ANDROMEDA_ARTIFACT, wallet, LocalConfig.ADDR_OVERRIDES[LocalConfig.ANDROMEDA_ARTIFACT]);

  for (const folder of fs.readdirSync(tcbInfoFolder)) {    
    const tcbInfoFile = fs.readdirSync(tcbInfoFolder+"/"+folder).filter(file => file.endsWith(".json"))[0];
    const tcbInfo = JSON.parse(fs.readFileSync(tcbInfoFolder+"/"+folder+"/"+tcbInfoFile, 'utf8')) as TCBInfoStruct.TCBInfoStruct.tcbInfo;

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
