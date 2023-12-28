import net from "net";
import fs from 'fs';

import { ethers, JsonRpcProvider } from "ethers";

import { LocalConfig, attach_artifact, deploy_artifact, ADDR_OVERRIDES } from "./common.ts"

async function main() {
  const socket = net.connect({port: "5556"});

  let resp = await sendToKettle(socket, "advance");
  if (resp !== 'advanced') {
    throw("kettle did not advance, refusing to continue: "+resp);
  }

  const provider = new JsonRpcProvider(LocalConfig.RPC_URL);
  const wallet = new ethers.Wallet(LocalConfig.PRIVATE_KEY, provider);

  /* Assumes andromeda is configured, might not be */
  const Andromeda = await attach_artifact(LocalConfig.ANDROMEDA_ARTIFACT, wallet, ADDR_OVERRIDES[LocalConfig.ANDROMEDA_ARTIFACT]);
  const KM = await deploy_artifact(LocalConfig.KEY_MANAGER_SN_ARTIFACT, wallet, Andromeda.target);

  let keyManagerPub = await KM.xPub();
  if (keyManagerPub !== "0x0000000000000000000000000000000000000000") {
    throw("Key manager already bootstrapped with "+keyManagerPub);
  }

  const bootstrapTxData = await KM.offchain_Bootstrap.populateTransaction();
  resp = await sendToKettle(socket, 'execute {"caller":"0x0000000000000000000000000000000000000000","gas_limit":21000000,"gas_price":"0x0","transact_to":{"Call":"'+bootstrapTxData.to+'"},"value":"0x0","data":"'+bootstrapTxData.data+'","nonce":0,"chain_id":null,"access_list":[],"gas_priority_fee":null,"blob_hashes":[],"max_fee_per_blob_gas":null}');

  const executionResult = JSON.parse(resp);
  if (executionResult.Success === undefined) {
    throw("execution did not succeed: "+JSON.stringify(resp));
  }
  
  const offchainBootstrapResult = KM.interface.decodeFunctionResult(KM.offchain_Bootstrap.fragment, executionResult.Success.output.Call).toObject();

  const onchainBootstrapTx = await (await KM.onchain_Bootstrap(offchainBootstrapResult._xPub, offchainBootstrapResult.att)).wait();
  console.log("bootstrapped "+offchainBootstrapResult._xPub+" in "+onchainBootstrapTx.hash);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

/* Utils */
async function sendToKettle(s: net.Socket, cmd: string): Promise<string> {
  return new Promise((resolve) => {
    let outBuf = "";
    s.on('data', function(b) {
      outBuf += b.toString("utf-8");
      if (outBuf.endsWith("\n")) {
        resolve(outBuf.trim().replace(/^"|"$/gm,''));
      }
    });
    s.write(cmd+"\n");
  });
}
