import * as LocalConfig from '../deployment.json'

import { execSync } from "child_process";

import { artifacts } from "./common.ts";

function verify_contract(constructor_args, contract_addr, contract_name) {
  let cmd = "forge v --verifier blockscout --verifier-url https://explorer.rigil.suave.flashbots.net/api"+(constructor_args.length > 0? " --constructor-args "+constructor_args.join(","):"")+" "+contract_addr+" "+contract_name+" --compiler-version v0.8.19";
  console.log("Running ", cmd);
  execSync(cmd);
}

async function verify_all() {
  let all_artifacts = artifacts();
  Object.keys(all_artifacts).forEach(artifact_path => {
    let artifact = all_artifacts[artifact_path];
    let artifact_name = artifact_path.match(/([^\/]*).json/)[1];
    console.log("Verifying the following: ", (artifact["constructor_args"], artifact["address"], artifact_name));
    verify_contract(artifact["constructor_args"], artifact["address"], artifact_name);
  });
}

verify_all().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
