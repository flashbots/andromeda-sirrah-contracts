import { useEffect, useState, useRef } from "react";
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
} from "viem";
import * as LocalConfig from "../../../deployment.json";
import { kettle_advance, kettle_execute } from "../../../scripts/common.ts";
import Timelock from "../../../out/Timelock.sol/Timelock.json";

import { Provider } from "../../common/Suave";
import {
  ConsoleLog,
  log_font_color,
  format_explorer_link,
  format_revert_string,
  pretty_print_contract_call,
  pretty_print_contract_result,
} from "../../common/ConsoleLog";
import { ConnectContract } from "../../common/Contracts";

function TimelockContract(suaveProvider, suaveWallet, updateConsoleLog) {
  return ConnectContract(
    suaveProvider,
    suaveWallet,
    Timelock,
    LocalConfig.ADDR_OVERRIDES[LocalConfig.TIMELOCK_ARTIFACT],
    updateConsoleLog,
  );
}

function App() {
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
  const [message, setMessage] = useState("");

  const [consoleLog, updateConsoleLog] = ConsoleLog();
  const [suaveProvider, suaveWallet] = Provider(updateConsoleLog);

  const [isTimelockInitialized, timelock] = TimelockContract(
    suaveProvider,
    suaveWallet,
    updateConsoleLog,
  );

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
        <br />
        <div>
          No Rigil money? Get some at{" "}
          <a href="https://faucet.rigil.suave.flashbots.net" target="_blank">
            the faucet
          </a>
        </div>
      </div>
    </>
  );
}

function assert(condition: unknown, msg?: string): asserts condition {
  if (condition === false) throw new Error(msg);
}

export default App;
