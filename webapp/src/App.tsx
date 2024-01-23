import { useEffect, useState } from 'react'
import flashbotsLogo from './assets/flashbots.png'
import './App.css'
import { 
  decodeFunctionResult,
  encodeFunctionData,
  fromHex,
  getContract,
  HttpTransport,
  http,
  toHex,
  keccak256,
} from "viem/src/index"
import {
  getSuaveProvider,
  getSuaveWallet,
  SuaveProvider,
} from "viem/src/chains/utils/index"
import * as LocalConfig from '../../deployment.json'
import { kettle_advance, kettle_execute } from "../../scripts/common.ts"
import Timelock from "../../out/Timelock.sol/Timelock.json"

function App() {
  const [isTimelockInitialized, setIsTimelockInitialized] = useState<boolean | undefined>()
  const [messagePromptHidden, setMessagePromptHidden] = useState<boolean | undefined>()
  const [deadline, setDeadline] = useState<bigint>(60n)
  const [encryptedMessage, setEncryptedMessage] = useState<string | undefined>()
  const [decryptedMessage, setDecryptedMessage] = useState<string | undefined>()
  const [suaveProvider, setSuaveProvider] = useState<SuaveProvider<HttpTransport>>()
  const [message, setMessage] = useState("");
  const [timelock, setTimelock] = useState<any | undefined>();

  // only runs once
  useEffect(() => {
    const suaveProvider = getSuaveProvider(http(LocalConfig.RPC_URL))
    const suaveWallet = getSuaveWallet({
      transport: http(LocalConfig.RPC_URL),
      privateKey: LocalConfig.PRIVATE_KEY as '0x{string}',
    })
    setSuaveProvider(suaveProvider)

    // Create contract instance
    let ADDR_OVERRIDES: {[key: string]: any} = LocalConfig.ADDR_OVERRIDES;
    const timelock = getContract({
      address: ADDR_OVERRIDES[LocalConfig.TIMELOCK_ARTIFACT],
      abi: Timelock.abi,
      publicClient: suaveProvider, 
      walletClient: suaveWallet,
    })
    setTimelock(timelock)
  }, [])

  useEffect(() => {
    checkTimelockIsInitialized()
  }, [timelock]);

  useEffect(() => {
    const interval = setInterval(async () => {
      if (encryptedMessage && !decryptedMessage) {
        const timeout = await fetchDeadline();
        if (timeout != undefined && timeout <= 0n) {
          const message = await decryptMessage(encryptedMessage)
          setDecryptedMessage(message);
          clearInterval(interval)
        }
      }
    }, 1000); // Update every second

    // Clean up the interval on component unmount
    return () => clearInterval(interval);
  }, [encryptedMessage]); // Re-run the effect when `encryptedMessage` changes

  async function checkTimelockIsInitialized() {
    const isInitialized = await timelock?.read.isInitialized()
    if (isInitialized) {
      console.log("Timelock is initialized")
      setIsTimelockInitialized(true)
    } else {
      console.log("Timelock is still not initialized")
      setIsTimelockInitialized(false)
    }
  }

  async function submitEncryptedMessage(message: string) {
    const encryptedMessage = await timelock?.read.encryptMessage([
      message.padEnd(message.length+32-message.length%32),
      toHex(crypto.getRandomValues(new Uint8Array(32)))
    ]);
    await timelock.write.submitEncrypted([encryptedMessage])

    return encryptedMessage
  }

  async function fetchDeadline() {
    if( typeof encryptedMessage != 'undefined' ) {
      const deadline = await timelock.read.deadlines([keccak256(encryptedMessage as '0x{string}')]) as bigint;
      if(deadline == 0n) {
        return 60n
      }
      const block = await suaveProvider?.getBlock();
      const remainingBlocks = deadline - (block?.number ?? 0n);
      if (remainingBlocks <= 0) {
        setDeadline(0n)
        return 0n
      }
      const bigIntNeg = (...args: bigint[]) => args.reduce((e) => e < 0 ? e : 0n);
      const nowAsBigInt = BigInt(Math.floor(Date.now() / 1000));
      const timeout = bigIntNeg((block?.timestamp ?? nowAsBigInt) - nowAsBigInt) + remainingBlocks * 4n;
      setDeadline(timeout);
      return timeout;
    }
  }

  async function decryptMessage(encryptedMessage: string) {
    const server = LocalConfig.KETTLE_RPC;
    assert(typeof server == 'string', "web-based apps have to connect via http");

    let resp = await kettle_advance(server);
    if (resp !== 'advanced') {
      throw("kettle did not advance, refusing to continue: "+resp);
    }

    const data = encodeFunctionData({
      abi: timelock.abi,
      functionName: "decrypt",
      args: [
        encryptedMessage,
      ],
    })
    resp = await kettle_execute(server, timelock.address, data.toString());

    let executionResult = JSON.parse(resp);
    if (executionResult.Success === undefined) {
      throw("execution did not succeed: "+JSON.stringify(resp));
    }

    // @ts-expect-error
    const offchainDecryptResult = decodeFunctionResult({
      abi: timelock.abi,
      functionName: "decrypt",
      data: executionResult.Success.output.Call,
    }) as `0x${string}`;
    console.log("Successfully decrypted message: '"+fromHex(offchainDecryptResult, "string").trim()+"'");

    return fromHex(offchainDecryptResult, "string").trim();
  }

  return (
    <>
      <div>
        <a href="https://www.flashbots.net" target="_blank">
          <img src={flashbotsLogo} className="logo" alt="Flashbots logo" />
        </a>
      </div>
      <div className="card">
        {isTimelockInitialized && !messagePromptHidden && (
          <div>
            <input type="text" value={message} onChange={(e) => setMessage(e.target.value)} />
          </div>
        )}
        <button onClick={async () => {
          if (isTimelockInitialized != true) {
            await checkTimelockIsInitialized()
          } else if (encryptedMessage === undefined) {
            setMessagePromptHidden(true);
            setEncryptedMessage(await submitEncryptedMessage(message))
          } else {
            setDecryptedMessage(await decryptMessage(encryptedMessage));
          }
        }}>
          {!messagePromptHidden && (
            <div>
            {isTimelockInitialized === undefined ? "Check if ": ""}Timelock is{isTimelockInitialized === undefined ? "" : isTimelockInitialized ? "" : " not yet"} initialized{isTimelockInitialized ? " - submit message":""}
            </div>
          )}
          {messagePromptHidden && deadline > 0n && (
            <div>
              Waiting {deadline?.toString()} seconds for timelock to expire...
            </div>
          )}
          {messagePromptHidden && deadline === 0n && (
            <div>
            {decryptedMessage === undefined ? "Decrypting message..." : "Decrypted message: '"+decryptedMessage+"'"}
            </div>
          )}
        </button>
      </div>
    </>
  )
}

function assert(condition: unknown, msg?: string): asserts condition {
  if (condition === false) throw new Error(msg)
}

export default App
