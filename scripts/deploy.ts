import fs from 'fs';

import { ethers, JsonRpcProvider } from "ethers";

import { TCBInfoStruct, EnclaveIdStruct } from "lib/automata-dcap-v3-attestation/typechain-types/contracts/AutomataDcapV3Attestation";

import { deploy_artifact } from "./common.ts"

import * as LocalConfig from '../deployment.json'


async function deploy() {
  const provider = new JsonRpcProvider(LocalConfig.RPC_URL);
  const wallet = new ethers.Wallet(LocalConfig.PRIVATE_KEY, provider);

  const [SigVerifyLib,] = await deploy_artifact(LocalConfig.SIGVERIFY_LIB_ARTIFACT, wallet);
  const [Bip32,] = await deploy_artifact(LocalConfig.BIP32_ARTIFACT, wallet);

  const [Andromeda, andomedaFound] = await deploy_artifact(LocalConfig.ANDROMEDA_ARTIFACT, wallet, SigVerifyLib.target);

  if (andomedaFound) { 
    console.log("Andromeda already deployed, not configuring it");
  } else {
    const enclaveId = JSON.parse(fs.readFileSync(LocalConfig.QE_IDENTITY_FILE, 'utf8')) as EnclaveIdStruct.EnclaveIdStruct;
    const enclaveIdTx = await (await Andromeda.configureQeIdentityJson(enclaveId)).wait();
    console.log("configured QeIdentidy in "+enclaveIdTx.hash);

    for (let i = 0; i < LocalConfig.TRUSTED_MRENCLAVES.length; i++) {
      const tx = await (await Andromeda.setMrEnclave(LocalConfig.TRUSTED_MRENCLAVES[i], true)).wait();
      console.log("Set mr_enclave "+LocalConfig.TRUSTED_MRENCLAVES[i]+" as trusted in "+tx.hash);
    }

    for (let i = 0; i < LocalConfig.TRUSTED_MRSIGNERS.length; i++) {
      const tx = await (await Andromeda.setMrSigner(LocalConfig.TRUSTED_MRSIGNERS[i], true)).wait();
      console.log("Set mr_signer "+LocalConfig.TRUSTED_MRSIGNERS[i]+" as trusted in "+tx.hash);
    }
  }

  const [KeyManagerSN,] = await deploy_artifact(LocalConfig.KEY_MANAGER_SN_ARTIFACT, wallet, Andromeda.target, Bip32.target);
}

deploy().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
