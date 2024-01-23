import net from "net";

import { ethers, JsonRpcProvider } from "ethers";

import { connect_kettle, deploy_artifact, deploy_artifact_direct, attach_artifact, kettle_advance, kettle_execute } from "./common"

import * as LocalConfig from '../deployment.json'

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

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
  const ADDR_OVERRIDES: {[key: string]: string} = LocalConfig.ADDR_OVERRIDES;
  const KM = await attach_artifact(LocalConfig.KEY_MANAGER_SN_ARTIFACT, wallet, ADDR_OVERRIDES[LocalConfig.KEY_MANAGER_SN_ARTIFACT]);

  const SealedAuction = await deploy_artifact_direct(LocalConfig.SEALED_AUCTION_ARTIFACT, wallet, KM.target, 5);
  await kettle_advance(kettle);

  await deriveKey(await SealedAuction.getAddress(), kettle, KM);
  await testSA(SealedAuction, kettle);

  const [Timelock, foundTL] = await deploy_artifact(LocalConfig.TIMELOCK_ARTIFACT, wallet, KM.target);
  if (!foundTL) {
    await kettle_advance(kettle);
    await deriveKey(await Timelock.getAddress(), kettle, KM);
  }
  await testTL(Timelock, kettle);
}

async function deriveKey(address: string, kettle: net.Socket | string, KM: ethers.Contract) {
  const offchainDeriveTxData = await KM.offchain_DeriveKey.populateTransaction(address);
  let resp = await kettle_execute(kettle, offchainDeriveTxData.to, offchainDeriveTxData.data);

  let executionResult = JSON.parse(resp);
  if (executionResult.Success === undefined) {
    throw("execution did not succeed: "+JSON.stringify(resp));
  }

  const offchainDeriveResult = KM.interface.decodeFunctionResult(KM.offchain_DeriveKey.fragment, executionResult.Success.output.Call).toObject();
  const onchainDeriveTx = await (await KM.onchain_DeriveKey(address, offchainDeriveResult.dPub, offchainDeriveResult.sig)).wait();

  console.log("submitted derive key for "+address+" in "+onchainDeriveTx.hash);  
}

deploy().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
