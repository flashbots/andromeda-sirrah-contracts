import net from "net";

import { ethers, JsonRpcProvider } from "ethers";

import { deploy_artifact, deploy_artifact_direct, attach_artifact, kettle_advance, kettle_execute } from "./common"

import * as LocalConfig from '../deployment.json'

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

async function testSA(SealedAuction: ethers.Contract, socket: net.Socket) {
  console.log("Testing sealed auction contract...");

  const encryptedOrder = await SealedAuction.encryptOrder(2,ethers.zeroPadBytes("0xdead2123",32));
  await (await SealedAuction.submitEncrypted(encryptedOrder)).wait();

  await sleep(10000);

  await (await SealedAuction.advance()).wait();
  let resp = await kettle_advance(socket);
  if (resp !== 'advanced') {
    throw("kettle did not advance, refusing to continue: "+resp);
  }

  const offchainFinalizeTxData = await SealedAuction.offchain_Finalize.populateTransaction();
  resp = await kettle_execute(socket, offchainFinalizeTxData.to, offchainFinalizeTxData.data);

  let executionResult = JSON.parse(resp);
  if (executionResult.Success === undefined) {
    throw("execution did not succeed: "+JSON.stringify(resp));
  }

  const offchainFinalizeResult = SealedAuction.interface.decodeFunctionResult(SealedAuction.offchain_Finalize.fragment, executionResult.Success.output.Call).toObject();

  await (await SealedAuction.onchain_Finalize(offchainFinalizeResult.secondPrice_, offchainFinalizeResult.att)).wait();

  console.log("successfully finalized auction with '"+offchainFinalizeResult.secondPrice_+"' as second price");
}

async function testTL(Timelock: ethers.Contract, socket: net.Socket) {
  console.log("Testing timelock contract...");

  // Tests Timelock contract
  let message = "Suave timelock test message!32xr";
  const encryptedMessage = await Timelock.encryptMessage(message,ethers.zeroPadBytes("0xdead2123",32));
  const submitEncryptedTx = await (await Timelock.submitEncrypted(encryptedMessage)).wait();

  console.log("submitted encrypted message "+encryptedMessage+" in "+submitEncryptedTx.hash);

  await sleep(66000);

  await (await Timelock.advance()).wait();
  let resp = await kettle_advance(socket);
  if (resp !== 'advanced') {
    throw("kettle did not advance, refusing to continue: "+resp);
  }

  const offchainDecryptTxData = await Timelock.decrypt.populateTransaction(encryptedMessage);
  resp = await kettle_execute(socket, offchainDecryptTxData.to, offchainDecryptTxData.data);

  let executionResult = JSON.parse(resp);
  if (executionResult.Success === undefined) {
    throw("execution did not succeed: "+JSON.stringify(resp));
  }

  const offchainDecryptResult = Timelock.interface.decodeFunctionResult(Timelock.decrypt.fragment, executionResult.Success.output.Call).toObject();
  console.log("successfully decrypted message: '"+ethers.toUtf8String(offchainDecryptResult.message)+"'");
}

async function deploy() {
  const socket = net.connect({port: 5556, host: process.env.KETTLE_HOST});

  let resp = await kettle_advance(socket);
  if (resp !== 'advanced') {
    throw("kettle did not advance, refusing to continue: "+resp);
  }
  const provider = new JsonRpcProvider(LocalConfig.RPC_URL);
  const wallet = new ethers.Wallet(LocalConfig.PRIVATE_KEY, provider);
  const ADDR_OVERRIDES: {[key: string]: string} = LocalConfig.ADDR_OVERRIDES;
  const KM = await attach_artifact(LocalConfig.KEY_MANAGER_SN_ARTIFACT, wallet, ADDR_OVERRIDES[LocalConfig.KEY_MANAGER_SN_ARTIFACT]);

  const SealedAuction = await deploy_artifact_direct(LocalConfig.SEALED_AUCTION_ARTIFACT, wallet, KM.target, 5);
  await deriveKey(await SealedAuction.getAddress(), socket, KM);
  await testSA(SealedAuction, socket);

  const [Timelock, foundTL] = await deploy_artifact(LocalConfig.TIMELOCK_ARTIFACT, wallet, KM.target);
  if (!foundTL) {
    await deriveKey(await Timelock.getAddress(), socket, KM);
  }
  await testTL(Timelock, socket);
}

async function deriveKey(address: string, socket: net.Socket, KM: ethers.Contract) {
  const offchainDeriveTxData = await KM.offchain_DeriveKey.populateTransaction(address);
  let resp = await kettle_execute(socket, offchainDeriveTxData.to, offchainDeriveTxData.data);

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
