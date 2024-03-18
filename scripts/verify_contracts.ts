import * as LocalConfig from '../deployment.json'

import { execSync } from "child_process";

function verify_contract(constructor_args, contract_addr, contract_name) {
  let cmd = "forge v --verifier blockscout --verifier-url https://explorer.rigil.suave.flashbots.net/api"+(constructor_args.length > 0? " --constructor-args "+constructor_args.join(","):"")+" "+contract_addr+" "+contract_name+" --compiler-version v0.8.19";
  console.log("Running ", cmd);
  let o = execSync(cmd);
}

async function verify_all() {
  Object.keys(LocalConfig).filter(key => key.endsWith("ARTIFACT")).filter(key => LocalConfig["ADDR_OVERRIDES"][LocalConfig[key]]).filter(key => LocalConfig["CONSTRUCTOR_ARGS"][LocalConfig[key]]).forEach(key => {
    let artifact_addr = LocalConfig["ADDR_OVERRIDES"][LocalConfig[key]];
    let artifact_path = LocalConfig[key];
    let artifact_name = artifact_path.match(/([^\/]*).json/)[1];
    let constructor_args = LocalConfig["CONSTRUCTOR_ARGS"][LocalConfig[key]];
    console.log("Verifying the following: ", (constructor_args, artifact_addr, artifact_name));
    verify_contract(constructor_args, artifact_addr, artifact_name);
  });
}

verify_all().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
