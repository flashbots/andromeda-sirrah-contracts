import net from "net";

import { ethers, JsonRpcProvider } from "ethers";

import { artifact_addr, connect_kettle, attach_artifact, deploy_artifact, kettle_execute, kettle_advance} from "./common"

import * as LocalConfig from '../deployment.json'

async function main() {
  const kettle = connect_kettle(LocalConfig.KETTLE_RPC);

  await kettle_advance(kettle);

  const provider = new JsonRpcProvider(LocalConfig.RPC_URL);
  const wallet = new ethers.Wallet(LocalConfig.PRIVATE_KEY, provider);

  /* Assumes andromeda is configured, might not be */
  const Andromeda = await attach_artifact(LocalConfig.ANDROMEDA_ARTIFACT, wallet, artifact_addr(LocalConfig.ANDROMEDA_ARTIFACT));
  const [KM, _] = await deploy_artifact(LocalConfig.KEY_MANAGER_SN_ARTIFACT, wallet, Andromeda.target);

  let keyManagerPub = await KM.xPub();
  if (keyManagerPub !== "0x0000000000000000000000000000000000000000") {
    console.log("Key manager already bootstrapped with "+keyManagerPub);
    return
  }
  // 1st. Bootstrap the key manager
  await kettle_advance(kettle);
  const bootstrapTxData = await KM.offchain_Bootstrap.populateTransaction();
  let resp = await kettle_execute(kettle, bootstrapTxData.to, bootstrapTxData.data);

  const executionResult = JSON.parse(resp);
  if (executionResult.Success === undefined) {
    throw("execution did not succeed: "+JSON.stringify(resp));
  }
  
  const offchainBootstrapResult = KM.interface.decodeFunctionResult(KM.offchain_Bootstrap.fragment, executionResult.Success.output.Call).toObject();

  const onchainBootstrapTx = await (await KM.onchain_Bootstrap(offchainBootstrapResult._xPub, offchainBootstrapResult.att)).wait();
  console.log("bootstrapped "+offchainBootstrapResult._xPub+" in "+onchainBootstrapTx.hash);

  // 2nd. Register the key manager
  await kettle_advance(kettle);
  const registerTxData = await KM.offchain_Register.populateTransaction();
  resp = await kettle_execute(kettle, registerTxData.to, registerTxData.data);

  const registerResult = JSON.parse(resp);
  if (registerResult.Success === undefined) {
    throw("registration did not succeed: "+JSON.stringify(resp));
  }

  const offchainRegisterResult = KM.interface.decodeFunctionResult(KM.offchain_Register.fragment, registerResult.Success.output.Call).toObject();

  const onchainRegisterTx = await (await KM.onchain_Register(offchainRegisterResult.addr, offchainRegisterResult.myPub, offchainRegisterResult.att)).wait();
  console.log("registered "+offchainRegisterResult.addr+" with the pubkey "+offchainRegisterResult.myPub+" in "+onchainRegisterTx.hash);

  // 3rd onboard the key manager
  await kettle_advance(kettle);
  const onboardTxData = await KM.offchain_Onboard.populateTransaction(offchainRegisterResult.addr);
  resp = await kettle_execute(kettle, onboardTxData.to, onboardTxData.data);

  const onboardResult = JSON.parse(resp);
  if (onboardResult.Success === undefined) {
    throw("onboarding did not succeed: "+JSON.stringify(resp));
  }

  const offchainOnboardResult = KM.interface.decodeFunctionResult(KM.offchain_Onboard.fragment, onboardResult.Success.output.Call).toObject();

  const onchainOnboardTx = await (await KM.onchain_Onboard(offchainRegisterResult.addr, offchainOnboardResult.ciphertext)).wait();
  console.log("onboarded "+offchainRegisterResult.addr+" in "+onchainOnboardTx.hash);

}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
