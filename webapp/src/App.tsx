import { useEffect, useState } from "react";
import flashbotsLogo from "./assets/flashbots.png";
import "./App.css";
import { useSDK } from "@metamask/sdk-react";
import {
  decodeFunctionResult,
  decodeFunctionData,
  encodeFunctionData,
  fromHex,
  getAbiItem,
  getContract,
  toHex,
  keccak256,
  createPublicClient,
  createWalletClient,
  custom,
  http,
  defineChain,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import * as LocalConfig from "../../deployment.json";
import { kettle_advance, kettle_execute } from "../../scripts/common.ts";
import Timelock from "../../out/Timelock.sol/Timelock.json";

function App() {
  const [isTimelockInitialized, setIsTimelockInitialized] = useState<
    boolean | undefined
  >();
  const [messagePromptHidden, setMessagePromptHidden] = useState<
    boolean | undefined
  >();
  const [deadline, setDeadline] = useState<bigint>(60n);
  const [encryptedMessage, setEncryptedMessage] = useState<
    string | undefined
  >();
  const [decryptedMessage, setDecryptedMessage] = useState<
    string | undefined
  >();
  const [suaveProvider, setSuaveProvider] = useState<any>();
  const [suaveWallet, setSuaveWallet] = useState<any>();
  const [message, setMessage] = useState("");
  const [timelock, setTimelock] = useState<any | undefined>();
  const [consoleLog, setConsoleLog] = useState<string>("");

  function updateConsoleLog(newLog: string) {
    const currentTime = new Date().toLocaleString("en-US", {
      hour: "numeric",
      minute: "numeric",
      second: "numeric",
      hour12: false,
    });
    setConsoleLog(
      (consoleLog) =>
        log_font_color("lightgrey", "[" + currentTime + "]: ") +
        newLog +
        "<br>" +
        consoleLog,
    );
  }

  useEffect(() => {
    return () => {
      setConsoleLog("");
    };
  }, []);


  async function connectMetamask() {
    const [account] = await window.ethereum!.request({
      method: "eth_requestAccounts",
    });
    await window.ethereum!.request({
      method: "wallet_addEthereumChain",
      params: [
        {
          chainId: "0x1008c45",
          chainName: "rigil",
          rpcUrls: ["https://rpc.rigil.suave.flashbots.net"],
        },
      ],
    });

    const suaveWallet = createWalletClient({
      account,
      chain: rigilChain,
      transport: custom(window.ethereum!),
    });

    updateConsoleLog("Using Metamask with account "+format_explorer_link({address: account}));
    setSuaveWallet(suaveWallet);
  }

  useEffect(() => {
    /* if LocalConfig.PRIVATE_KEY is provided, use it, otherwise connect to Metamask */
    console.log(LocalConfig.PRIVATE_KEY.length);
    if (LocalConfig.PRIVATE_KEY.length == 66) {
      const account = privateKeyToAccount(LocalConfig.PRIVATE_KEY);
      const suaveWallet = createWalletClient({
        account,
        chain: rigilChain,
        transport: http(LocalConfig.RPC_URL),
      });

      updateConsoleLog("Using local private key for "+format_explorer_link({address: account.address}));
      setSuaveWallet(suaveWallet);
    } else {
      connectMetamask().catch((e) => {
        console.log("could not connect metamask: ", e);
        throw new Error("could not connect metamask: " + e.message);
      });
    }
  }, []);

  useEffect(() => {
    const suaveProvider = createPublicClient({
      chain: rigilChain,
      transport: http(LocalConfig.RPC_URL),
    });
    updateConsoleLog("Connected to SUAVE Rigil RPC at " + LocalConfig.RPC_URL);
    setSuaveProvider(suaveProvider);
  }, []);

  useEffect(() => {
    if (suaveProvider == undefined || suaveWallet == undefined) {
      return;
    }
    // Create contract instance
    const ADDR_OVERRIDES: { [key: string]: any } = LocalConfig.ADDR_OVERRIDES;
    const timelock = getContract({
      address: ADDR_OVERRIDES[LocalConfig.TIMELOCK_ARTIFACT],
      abi: Timelock.abi,
      client: {
        public: suaveProvider,
        wallet: suaveWallet,
      },
    });
    updateConsoleLog(
      "Using Timelock contract at " +
        format_explorer_link({ address: timelock.address }),
    );
    setTimelock(timelock);
  }, [suaveProvider, suaveWallet]);

  useEffect(() => {
    if (isTimelockInitialized) {
      return;
    }

    checkTimelockIsInitialized();
    const timerCheckTimelockIsInitialized = setInterval(async () => {
      await checkTimelockIsInitialized(isTimelockInitialized);
    }, 1000); // Update every second

    // Clean up the interval on component unmount
    return () => {
      clearInterval(timerCheckTimelockIsInitialized);
    };
  }, [timelock, isTimelockInitialized]);

  async function checkTimelockIsInitialized(isTimelockInitialized) {
    if (isTimelockInitialized) {
      return;
    }

    const isInitialized = await timelock?.read.isInitialized();
    if (isInitialized) {
      updateConsoleLog("Timelock contract is initialized properly");
      setIsTimelockInitialized(true);
    } else {
      console.log("Timelock is still not initialized");
      setIsTimelockInitialized(false);
    }
  }

  useEffect(() => {
    if (!encryptedMessage || decryptedMessage) {
      return;
    }

    const deadlineFetch = setInterval(async () => {
      await fetchDeadline();
    }, 1000); // Update every second

    const decryptionAttempt = setInterval(async () => {
      const timeout = await fetchDeadline();
      try {
        const message = await decryptMessage(encryptedMessage);
        updateConsoleLog("Decrypted message is: " + message);
        setDecryptedMessage(message);
        clearInterval(deadlineFetch);
        clearInterval(decryptionAttempt);
      } catch (e) {
        updateConsoleLog(
          "Failed to decrypt message " +
            timeout?.toString() +
            " seconds before deadline: " +
            log_font_color("red", e.message),
        );
      }
    }, 10000); // Try to decrypt every 10 seconds

    // Clean up the interval on component unmount
    return () => {
      clearInterval(deadlineFetch);
      clearInterval(decryptionAttempt);
    };
  }, [decryptedMessage, encryptedMessage]); // Re-run the effect when `encryptedMessage` changes

  async function submitEncryptedMessage(message: string) {
    const encryptMsgArgs = [
      message.padEnd(message.length + 32 - (message.length % 32)),
      toHex(crypto.getRandomValues(new Uint8Array(32))),
    ];
    const encryptedMessage =
      await timelock?.read.encryptMessage(encryptMsgArgs);
    const encryptAbi = getAbiItem({
      abi: timelock.abi,
      name: "encryptMessage",
    });
    updateConsoleLog(
      "Encrypted message to the Timelock contract: " +
        pretty_print_contract_call(encryptAbi, encryptMsgArgs) +
        " -> [bytes: " +
        encryptedMessage +
        "]",
    );

    const tx = await timelock.write.submitEncrypted([encryptedMessage]);
    updateConsoleLog(
      "Submited encrypted message to the chain: " +
        format_explorer_link({ tx: tx }),
    );

    return encryptedMessage;
  }

  async function fetchDeadline() {
    if (typeof encryptedMessage != "undefined") {
      const msgDeadline = (await timelock.read.deadlines([
        keccak256(encryptedMessage as "0x{string}"),
      ])) as bigint;
      if (msgDeadline == 0n) {
        return 60n;
      }
      const block = await suaveProvider?.getBlock();
      const remainingBlocks = msgDeadline - (block?.number ?? 0n);
      if (remainingBlocks <= 0) {
        setDeadline(0n);
        return 0n;
      }
      const bigIntNeg = (...args: bigint[]) =>
        args.reduce((e) => (e < 0 ? e : 0n));
      const nowAsBigInt = BigInt(Math.floor(Date.now() / 1000));
      const timeout =
        bigIntNeg((block?.timestamp ?? nowAsBigInt) - nowAsBigInt) +
        remainingBlocks * 4n;
      setDeadline(timeout);
      return timeout;
    }
  }

  async function decryptMessage(encryptedMessage: string) {
    const server = LocalConfig.KETTLE_RPC;
    assert(
      typeof server == "string",
      "web-based apps have to connect via http",
    );

    await kettle_advance(server);

    const decryptAbi = getAbiItem({ abi: timelock.abi, name: "decrypt" });
    const data = encodeFunctionData({
      abi: [decryptAbi],
      args: [encryptedMessage],
    });

    const resp = await kettle_execute(
      server,
      timelock.address,
      data.toString(),
    );
    const callLog = pretty_print_contract_call(decryptAbi, [encryptedMessage]);

    const executionResult = JSON.parse(resp);
    if (executionResult.Success === undefined) {
      updateConsoleLog(
        "Kettle refused to decrypt the message: " +
          callLog +
          log_font_color(
            "red",
            ' error: "' +
              format_revert_string(executionResult.Revert.output) +
              '"',
          ),
      );
      throw new Error(
        "execution did not succeed: " +
          format_revert_string(executionResult.Revert.output),
      );
    }

    const callResLog = pretty_print_contract_result(
      decryptAbi,
      executionResult.Success.output.Call,
    );
    updateConsoleLog(
      "Requested decryption from kettle: " + callLog + " -> " + callResLog,
    );

    const offchainDecryptResult = decodeFunctionResult({
      abi: [decryptAbi],
      data: executionResult.Success.output.Call,
    }) as `0x${string}`;
    console.log(
      "Successfully decrypted message: '" +
        fromHex(offchainDecryptResult, "string").trim() +
        "'",
    );

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
            <input
              type="text"
              value={message}
              onChange={(e) => setMessage(e.target.value)}
            />
          </div>
        )}
        {!messagePromptHidden && (
          <button
            onClick={async () => {
              if (isTimelockInitialized != true) {
                await checkTimelockIsInitialized(isTimelockInitialized);
              } else if (encryptedMessage === undefined) {
                setMessagePromptHidden(true);
                setEncryptedMessage(await submitEncryptedMessage(message));
              } else {
                setDecryptedMessage(await decryptMessage(encryptedMessage));
                updateConsoleLog("Decrypted message is: " + message);
              }
            }}
          >
            <div>
              {isTimelockInitialized === undefined ? "Check if " : ""}Timelock
              is
              {isTimelockInitialized === undefined
                ? ""
                : isTimelockInitialized
                  ? ""
                  : " not yet"}{" "}
              initialized{isTimelockInitialized ? " - submit message" : ""}
            </div>
          </button>
        )}

        {messagePromptHidden && deadline > 0n && (
          <div>
            Waiting {deadline?.toString()} seconds for timelock to expire...
          </div>
        )}
        {messagePromptHidden && deadline === 0n && (
          <div>
            {decryptedMessage === undefined
              ? "Decrypting message..."
              : "Decrypted message: " + decryptedMessage + ""}
          </div>
        )}

        <br />
        <br />
        <div
          className="textbox"
          dangerouslySetInnerHTML={{ __html: consoleLog }}
        ></div>
      </div>
    </>
  );
}

function assert(condition: unknown, msg?: string): asserts condition {
  if (condition === false) throw new Error(msg);
}

function pretty_print_contract_call(abi, inputs) {
  assert(abi.inputs.length == inputs.length);

  const fn = abi.type + " " + abi.name;
  let args = "";
  for (let i = 0; i < abi.inputs.length; i++) {
    args += abi.inputs[i].type + " " + abi.inputs[i].name + ": " + inputs[i];
    if (i + 1 != abi.inputs.length) {
      args += ", ";
    }
  }

  return fn + "(" + args + ")";
}

function pretty_print_contract_result(methodAbi, rawOutput: "0x{string}") {
  const decodedResult = decodeFunctionResult({
    abi: [methodAbi],
    data: rawOutput,
  });

  if (decodedResult == null) {
    throw new Error("unable to decode result");
  }

  if (typeof decodedResult != "object") {
    assert(methodAbi.outputs.length == 1);
    return (
      "[" +
      methodAbi.outputs[0].type +
      " " +
      methodAbi.outputs[0].name +
      ": " +
      decodedResult +
      "]"
    );
  }

  let res = "[";
  for (let i = 0; i < methodAbi.outputs.length; i++) {
    res +=
      methodAbi.outputs[i].type +
      " " +
      methodAbi.outputs[i].name +
      ": " +
      decodedResult[methodAbi.outputs[i].name];
    if (i + 1 != methodAbi.outputs.length) {
      res += ", ";
    }
  }

  res += "]";
  return res;
}

function format_revert_string(rawOutput: "0x{string}") {
  return decodeFunctionData({
    abi: [
      {
        inputs: [{ name: "error", type: "string" }],
        name: "Error",
        type: "function",
      },
    ],
    data: rawOutput,
  }).args[0];
}

function log_font_color(color: string, str: string) {
  return '<font color="' + color + '">' + str + "</font>";
}

// Sometimes TX
function format_explorer_link(target: { address?: string; tx?: string }) {
  const link =
    target.address !== undefined
      ? "https://explorer.rigil.suave.flashbots.net/address/" + target.address
      : "https://explorer.rigil.suave.flashbots.net/tx/" + target.tx;
  const value = target.address !== undefined ? target.address : target.tx;
  return '<a target="_blank" href=' + link + ">" + value + "</a>";
}

const rigilChain = defineChain({
  id: 16813125,
  name: "Rigil",
  rpcUrls: {
    default: {
      http: ["https://rpc.rigil.suave.flashbots.net"],
    },
  },
});

export default App;
