import net from "net";

import { ethers, JsonRpcProvider } from "ethers";

import { connect_kettle, deploy_artifact, deploy_artifact_direct, attach_artifact, kettle_advance, kettle_execute, derive_key } from "./common"

import * as LocalConfig from '../deployment.json'

async function deploy() {
  const kettle = connect_kettle(LocalConfig.KETTLE_RPC);

  const provider = new JsonRpcProvider(LocalConfig.RPC_URL);
  const wallet = new ethers.Wallet(LocalConfig.PRIVATE_KEY, provider);
  const ADDR_OVERRIDES: {[key: string]: string} = LocalConfig.ADDR_OVERRIDES;
  const KM = await attach_artifact(LocalConfig.KEY_MANAGER_SN_ARTIFACT, wallet, ADDR_OVERRIDES[LocalConfig.KEY_MANAGER_SN_ARTIFACT]);

  const [HttpCall, foundHC] = await deploy_artifact(LocalConfig.HTTPCALL_ARTIFACT, wallet, KM.target);
  const [BundleStore, foundBS] = await deploy_artifact(LocalConfig.BUNDLE_STORE_ARTIFACT, wallet, KM.target, []);
  const [Timelock, foundTL] = await deploy_artifact(LocalConfig.TIMELOCK_ARTIFACT, wallet, KM.target);
  /* Not currently used in demos */
  // const SealedAuction = await deploy_artifact_direct(LocalConfig.SEALED_AUCTION_ARTIFACT, wallet, KM.target, 5);

  await kettle_advance(kettle);

  if (!foundHC) {
    await derive_key(await HttpCall.getAddress(), kettle, KM);
  }
  if (!foundBS) {
    await derive_key(await BundleStore.getAddress(), kettle, KM);
  }
  if (!foundTL) {
    await derive_key(await Timelock.getAddress(), kettle, KM);
  }
  /* Not currently used in demos */
  // await derive_key(await SealedAuction.getAddress(), kettle, KM);
}

deploy().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
