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
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
