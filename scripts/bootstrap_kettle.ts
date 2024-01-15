import net from "net";

import { ethers, JsonRpcProvider } from "ethers";

import { attach_artifact, deploy_artifact, kettle_execute, kettle_advance} from "./common.ts"

import * as LocalConfig from '../deployment.json'

async function main() {
  const socket = net.connect({port: "5556"});

  let resp = await kettle_advance(socket);
  if (resp !== 'advanced') {
    throw("kettle did not advance, refusing to continue: "+resp);
  }

  const provider = new JsonRpcProvider(LocalConfig.RPC_URL);
  const wallet = new ethers.Wallet(LocalConfig.PRIVATE_KEY, provider);

  /* Assumes andromeda is configured, might not be */
  const Andromeda = await attach_artifact(LocalConfig.ANDROMEDA_ARTIFACT, wallet, LocalConfig.ADDR_OVERRIDES[LocalConfig.ANDROMEDA_ARTIFACT]);
  const [KM, _] = await deploy_artifact(LocalConfig.KEY_MANAGER_SN_ARTIFACT, wallet, Andromeda.target);

  let keyManagerPub = await KM.xPub();
  if (keyManagerPub !== "0x0000000000000000000000000000000000000000") {
    throw("Key manager already bootstrapped with "+keyManagerPub);
  }

  const bootstrapTxData = await KM.offchain_Bootstrap.populateTransaction();
  resp = await kettle_execute(socket, bootstrapTxData.to, bootstrapTxData.data);

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
