import net from "net";
import fs from 'fs';

import { ethers, JsonRpcProvider } from "ethers";

import { attach_artifact, deploy_artifact, sendToKettle} from "./common.ts"

import * as LocalConfig from '../deployment.json'

async function main() {
  const new_kettle_socket = net.connect({port: "5557"});
  const registered_kettle_socket = net.connect({port: "5556"});

  const provider = new JsonRpcProvider(LocalConfig.RPC_URL);
  const wallet = new ethers.Wallet(LocalConfig.PRIVATE_KEY, provider);

  /* Assumes andromeda is configured, might not be */
  const Andromeda = await attach_artifact(LocalConfig.ANDROMEDA_ARTIFACT, wallet, LocalConfig.ADDR_OVERRIDES[LocalConfig.ANDROMEDA_ARTIFACT]);
  const [KM, _] = await deploy_artifact(LocalConfig.KEY_MANAGER_SN_ARTIFACT, wallet, Andromeda.target);

  let resp = await sendToKettle(new_kettle_socket, "advance");
  if (resp !== 'advanced') {
    throw("kettle did not advance, refusing to continue: "+resp);
  }

  const registerTxData = await KM.offchain_Register.populateTransaction();
  resp = await sendToKettle(new_kettle_socket, 'execute {"caller":"0x0000000000000000000000000000000000000000","gas_limit":21000000,"gas_price":"0x0","transact_to":{"Call":"'+registerTxData.to+'"},"value":"0x0","data":"'+registerTxData.data+'","nonce":0,"chain_id":null,"access_list":[],"gas_priority_fee":null,"blob_hashes":[],"max_fee_per_blob_gas":null}');

  let executionResult = JSON.parse(resp);
  if (executionResult.Success === undefined) {
    throw("execution did not succeed: "+JSON.stringify(resp));
  }
  
  const offchainRegisterResult = KM.interface.decodeFunctionResult(KM.offchain_Register.fragment, executionResult.Success.output.Call).toObject();

  const onchainRegisterTx = await (await KM.onchain_Register(offchainRegisterResult.addr, offchainRegisterResult.myPub, offchainRegisterResult.att)).wait();
  console.log("registered "+offchainRegisterResult.addr+" in "+onchainRegisterTx.hash);

  resp = await sendToKettle(registered_kettle_socket, "advance");
  if (resp !== 'advanced') {
    throw("kettle did not advance, refusing to continue: "+resp);
  }

  const onboardTxData = await KM.offchain_Onboard.populateTransaction(offchainRegisterResult.addr);
  resp = await sendToKettle(registered_kettle_socket, 'execute {"caller":"0x0000000000000000000000000000000000000000","gas_limit":21000000,"gas_price":"0x0","transact_to":{"Call":"'+onboardTxData.to+'"},"value":"0x0","data":"'+onboardTxData.data+'","nonce":0,"chain_id":null,"access_list":[],"gas_priority_fee":null,"blob_hashes":[],"max_fee_per_blob_gas":null}');

  executionResult = JSON.parse(resp);
  if (executionResult.Success === undefined) {
    throw("execution did not succeed: "+JSON.stringify(resp));
  }

  const offchainOnboardResult = KM.interface.decodeFunctionResult(KM.offchain_Onboard.fragment, executionResult.Success.output.Call).toObject();

  const onchainOnboardTx = await (await KM.onchain_Onboard(offchainRegisterResult.addr, offchainOnboardResult.ciphertext)).wait();

  const finishOnboardTxData = await KM.finish_Onboard.populateTransaction(offchainOnboardResult.ciphertext);
  resp = await sendToKettle(new_kettle_socket, 'execute {"caller":"0x0000000000000000000000000000000000000000","gas_limit":21000000,"gas_price":"0x0","transact_to":{"Call":"'+finishOnboardTxData.to+'"},"value":"0x0","data":"'+finishOnboardTxData.data+'","nonce":0,"chain_id":null,"access_list":[],"gas_priority_fee":null,"blob_hashes":[],"max_fee_per_blob_gas":null}');
  
  executionResult = JSON.parse(resp);
  if (executionResult.Success === undefined) {
    throw("execution did not succeed: "+JSON.stringify(resp));
  }

  console.log("onboarded "+offchainRegisterResult.addr+" in "+onchainOnboardTx.hash);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
