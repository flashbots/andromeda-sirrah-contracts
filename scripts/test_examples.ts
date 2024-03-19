import net from "net";

import { ethers, JsonRpcProvider } from "ethers";

import { artifact_addr, connect_kettle, deploy_artifact, deploy_artifact_direct, attach_artifact, kettle_advance, kettle_execute, derive_key } from "./common"

import * as LocalConfig from '../deployment.json'

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

async function testHC(HttpCall: ethers.Contract, kettle: net.Socket | string) {
  console.log("Testing httpcall contract...");
  const httpcallData = await HttpCall.makeHttpCall.populateTransaction();

  let resp = await kettle_execute(kettle, httpcallData.to, httpcallData.data);

  let executionResult = JSON.parse(resp);
  if (executionResult.Success === undefined) {
    throw("execution did not succeed: "+JSON.stringify(resp));
  }

  const callResult = HttpCall.interface.decodeFunctionResult(HttpCall.makeHttpCall.fragment, executionResult.Success.output.Call);
  console.log("Response from http call:", callResult);
}

async function testSA(SealedAuction: ethers.Contract, kettle: net.Socket | string) {
  console.log("Testing sealed auction contract...");

  const encryptedOrder = await SealedAuction.encryptOrder(2,ethers.zeroPadBytes("0xdead2123",32));
  await (await SealedAuction.submitEncrypted(encryptedOrder)).wait();

  await sleep(10000);

  await kettle_advance(kettle);

  const offchainFinalizeTxData = await SealedAuction.offchain_Finalize.populateTransaction();
  let resp = await kettle_execute(kettle, offchainFinalizeTxData.to, offchainFinalizeTxData.data);

  let executionResult = JSON.parse(resp);
  if (executionResult.Success === undefined) {
    throw("execution did not succeed: "+JSON.stringify(resp));
  }

  const offchainFinalizeResult = SealedAuction.interface.decodeFunctionResult(SealedAuction.offchain_Finalize.fragment, executionResult.Success.output.Call).toObject();

  await (await SealedAuction.onchain_Finalize(offchainFinalizeResult.secondPrice_, offchainFinalizeResult.att)).wait();

  console.log("successfully finalized auction with '"+offchainFinalizeResult.secondPrice_+"' as second price");
}

async function testTL(Timelock: ethers.Contract, kettle: net.Socket | string) {
  console.log("Testing timelock contract...");

  // Tests Timelock contract
  let message = "Suave timelock test message!32xr";
  const encryptedMessage = await Timelock.encryptMessage(message,ethers.zeroPadBytes("0xdead2123",32));
  const submitEncryptedTx = await (await Timelock.submitEncrypted(encryptedMessage)).wait();

  console.log("submitted encrypted message "+encryptedMessage+" in "+submitEncryptedTx.hash);

  await sleep(72000);

  await kettle_advance(kettle);

  const offchainDecryptTxData = await Timelock.decrypt.populateTransaction(encryptedMessage);
  let resp = await kettle_execute(kettle, offchainDecryptTxData.to, offchainDecryptTxData.data);

  let executionResult = JSON.parse(resp);
  if (executionResult.Success === undefined) {
    throw("execution did not succeed: "+JSON.stringify(resp));
  }

  const offchainDecryptResult = Timelock.interface.decodeFunctionResult(Timelock.decrypt.fragment, executionResult.Success.output.Call).toObject();
  console.log("successfully decrypted message: '"+ethers.toUtf8String(offchainDecryptResult.message)+"'");
}

async function deploy() {
  const kettle = connect_kettle(LocalConfig.KETTLE_RPC);

  await kettle_advance(kettle);
  const provider = new JsonRpcProvider(LocalConfig.RPC_URL);
  const wallet = new ethers.Wallet(LocalConfig.PRIVATE_KEY, provider);
  const KM = await attach_artifact(LocalConfig.KEY_MANAGER_SN_ARTIFACT, wallet, artifact_addr(LocalConfig.KEY_MANAGER_SN_ARTIFACT));

  const [HttpCall, _] = await deploy_artifact(LocalConfig.HTTPCALL_ARTIFACT, wallet);
  await kettle_advance(kettle);

  await testHC(HttpCall, kettle);

  const [Timelock, foundTL] = await deploy_artifact(LocalConfig.TIMELOCK_ARTIFACT, wallet, KM.target);
  await kettle_advance(kettle);
  if (!foundTL) {
    await derive_key(await Timelock.getAddress(), kettle, KM);
    await kettle_advance(kettle);
  }
  await testTL(Timelock, kettle);

  const SealedAuction = await deploy_artifact_direct(LocalConfig.SEALED_AUCTION_ARTIFACT, wallet, KM.target, 5);
  await kettle_advance(kettle);

  await derive_key(await SealedAuction.getAddress(), kettle, KM);
  await testSA(SealedAuction, kettle);
}

deploy().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
