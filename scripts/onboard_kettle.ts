import net from "net";

import { ethers, JsonRpcProvider } from "ethers";

import { attach_artifact, deploy_artifact, kettle_execute, kettle_advance} from "./common.ts"

import * as LocalConfig from '../deployment.json'

async function main() {
  const new_kettle_socket = net.connect({port: "5556"});

  const provider = new JsonRpcProvider(LocalConfig.RPC_URL);
  const wallet = new ethers.Wallet(LocalConfig.PRIVATE_KEY, provider);

  /* Assumes andromeda is configured, might not be */
  const Andromeda = await attach_artifact(LocalConfig.ANDROMEDA_ARTIFACT, wallet, LocalConfig.ADDR_OVERRIDES[LocalConfig.ANDROMEDA_ARTIFACT]);
  const [KM, _] = await deploy_artifact(LocalConfig.KEY_MANAGER_SN_ARTIFACT, wallet, Andromeda.target);

  let resp = await kettle_advance(new_kettle_socket);
  if (resp !== 'advanced') {
    throw("kettle did not advance, refusing to continue: "+resp);
  }

  const registerTxData = await KM.offchain_Register.populateTransaction();
  resp = await kettle_execute(new_kettle_socket, registerTxData.to, registerTxData.data);

  let executionResult = JSON.parse(resp);
  if (executionResult.Success === undefined) {
    throw("execution did not succeed: "+JSON.stringify(resp));
  }
  
  const offchainRegisterResult = KM.interface.decodeFunctionResult(KM.offchain_Register.fragment, executionResult.Success.output.Call).toObject();

  let ciphertext = null;
  const onboard_event = (await KM.queryFilter("Onboard", 0))
    .map((e) => KM.interface.decodeEventLog("Onboard", e.data, e.topics))
    .filter((e) => e[0] === offchainRegisterResult.addr).pop();

  if (onboard_event) {
    console.log("onboard event for "+offchainRegisterResult.addr+" exists, skip registering ");

    ciphertext = onboard_event[1];
  } else {
    const registered_kettle_socket = net.connect({port: "5557"});

    const onchainRegisterTx = await (await KM.onchain_Register(offchainRegisterResult.addr, offchainRegisterResult.myPub, offchainRegisterResult.att)).wait();
    console.log("registered "+offchainRegisterResult.addr+" in "+onchainRegisterTx.hash);

    resp = await kettle_advance(registered_kettle_socket);
    if (resp !== 'advanced') {
      throw("kettle did not advance, refusing to continue: "+resp);
    }

    const onboardTxData = await KM.offchain_Onboard.populateTransaction(offchainRegisterResult.addr);
    resp = await kettle_execute(registered_kettle_socket, onboardTxData.to, onboardTxData.data);

    executionResult = JSON.parse(resp);
    if (executionResult.Success === undefined) {
      throw("execution did not succeed: "+JSON.stringify(resp));
    }

    const offchainOnboardResult = KM.interface.decodeFunctionResult(KM.offchain_Onboard.fragment, executionResult.Success.output.Call).toObject();

    const onchainOnboardTx = await (await KM.onchain_Onboard(offchainRegisterResult.addr, offchainOnboardResult.ciphertext)).wait();

    console.log("submitted onboard ciphertext for "+offchainRegisterResult.addr+" in "+onchainOnboardTx.hash);

    ciphertext = offchainOnboardResult.ciphertext;
  }

  const finishOnboardTxData = await KM.finish_Onboard.populateTransaction(ciphertext);
  resp = await kettle_execute(new_kettle_socket, finishOnboardTxData.to, finishOnboardTxData.data);

  executionResult = JSON.parse(resp);
  if (executionResult.Success === undefined) {
    throw("execution did not succeed: "+JSON.stringify(resp));
  }

  console.log("onboarded "+offchainRegisterResult.addr);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
