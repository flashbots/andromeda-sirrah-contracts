import { useEffect, useState } from 'react'
import reactLogo from './assets/react.svg'
// TODO: don't duplicate the ABI file; pull from build artifacts instead
import Timelock from './assets/Timelock.json'
import viteLogo from '/vite.svg'
import './App.css'
import { HttpTransport, encodeFunctionData, hexToBigInt, http } from "viem/src/index"
import {
  getSuaveProvider,
  getSuaveWallet,
  SuaveProvider,
  SuaveWallet,
  TransactionRequestSuave
} from "viem/src/chains/utils/index"

function App() {
  const [isTimelockInitialized, setIsTimelockInitialized] = useState<boolean | undefined>()
  const [suaveProvider, setSuaveProvider] = useState<SuaveProvider<HttpTransport>>()
  const [suaveWallet, setSuaveWallet] = useState<SuaveWallet<HttpTransport>>()
  const timelockAddress = "0xF45DA749ad6369d9C8bF70eac31041526E9dEFb1" // TODO: fill in w/ env var

  // only runs once
  useEffect(() => {
    const suaveProvider = getSuaveProvider(http("http://localhost:8545"))
    const suaveWallet = getSuaveWallet({
      transport: http("http://localhost:8545"),
      privateKey: "0x91ab9a7e53c220e6210460b65a7a3bb2ca181412a8a7b43ff336b3df1737ce12",
    })
    setSuaveProvider(suaveProvider)
    setSuaveWallet(suaveWallet)
  }, [])

  async function getTimelockIsInitialized() {
    const timelockCall = encodeFunctionData({
      abi: Timelock.abi,
      functionName: "isInitialized",
    })
    const tx: TransactionRequestSuave = {
      to: timelockAddress,
      data: timelockCall,
      // only necessary bc of a bug in suave-viem
      gasPrice: 10n * 1000000000n,
      gas: 300000n,
      type: "0x0",
    }
    const res = await suaveProvider?.call({
      ...tx,
      account: suaveWallet?.account,
    })
    return res
  }

  async function submitEncryptedOrder() {
    const ciph = "0xf00000000baaaaaaaaaaa77777777777" // TODO: get from timelock.encryptMessage(message,bytes32)
    const tx: TransactionRequestSuave = {
      type: "0x43",
      confidentialInputs: "0x",
      to: timelockAddress,
      data: encodeFunctionData({
        abi: Timelock.abi,
        functionName: "submitEncrypted",
        args: [
          ciph,
        ],
      }),
      gasPrice: 10n * 1000000000n,
      gas: 300000n,
    }
    const res = await suaveWallet?.sendTransaction(tx)
  }

  /* TODO: replicate this:
  assertEq(timelock.isInitialized(), true);

  // Submit encrypted orders
  string memory message = "Suave timelock test message!32xr";
  bytes memory ciph = timelock.encryptMessage(
      message,
      bytes32(uint(0xdead2123))
  );
  timelock.submitEncrypted(ciph);

  vm.roll(60);

  // Off chain compute the solution
  bytes memory output = timelock.decrypt(ciph);
  string memory dec = string(output);
  assertEq(message, dec);
  */

  return (
    <>
      <div>
        <a href="https://vitejs.dev" target="_blank">
          <img src={viteLogo} className="logo" alt="Vite logo" />
        </a>
        <a href="https://react.dev" target="_blank">
          <img src={reactLogo} className="logo react" alt="React logo" />
        </a>
      </div>
      <div className="card">
        <button onClick={async () => {
          const isInitialized = await getTimelockIsInitialized()
          console.log(isInitialized)
          if (isInitialized?.data && hexToBigInt(isInitialized.data) == 0n) {
            console.log("Timelock is still not initialized")
            setIsTimelockInitialized(false)
          }
        }}>
          Timelock is{isTimelockInitialized === undefined ? " not" : isTimelockInitialized ? "" : " still not"} initialized
        </button>
        <p>
          Edit <code>src/App.tsx</code> and save to test
        </p>
      </div>
    </>
  )
}

export default App
