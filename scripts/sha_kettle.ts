import net from "net";

import { ethers, JsonRpcProvider } from "ethers";

import { connect_kettle, attach_artifact, deploy_artifact, kettle_execute, kettle_advance} from "./common"

import * as LocalConfig from '../deployment.json'

async function main() {
  const kettle = connect_kettle(LocalConfig.KETTLE_RPC);

  await kettle_advance(kettle);
  let test =  [116, 101 ,115 ,116];

  let resp = await kettle_execute(kettle, "0x0000000000000000000000000000000000050700", "0x74657374");
  console.log(resp);

  const executionResult = JSON.parse(resp);
  if (executionResult.Success === undefined) {
    throw("execution did not succeed: "+JSON.stringify(resp));
  }

  console.log(executionResult.Success.output.Call);
  
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
