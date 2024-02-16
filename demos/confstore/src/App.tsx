import { React, useEffect, useState, useRef } from "react";
import flashbotsLogo from "../../common/assets/flashbots.png";
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
import StoreContract from "../../../out/RedisConfidentialStore.sol/BundleConfidentialStore.json";

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

function ConnectStoreContract(suaveProvider, suaveWallet, updateConsoleLog) {
  return ConnectContract(
    suaveProvider,
    suaveWallet,
    StoreContract,
    LocalConfig.ADDR_OVERRIDES[LocalConfig.BUNDLE_STORE_ARTIFACT],
    updateConsoleLog,
  );
}

function BundleSubmission({
  updateConsoleLog,
  suaveProvider,
  suaveWallet,
  storeContract,
}) {
  const [formValues, setFormValues] = useState({
    height: "10",
    transaction: "0x",
    profit: "10",
  });

  const handleChange = (e) => {
    setFormValues({
      ...formValues,
      [e.target.name]: e.target.value,
    });
  };

  const handleSubmit = async (e) => {
    e.preventDefault();

    const encryptedBundleBytes = await storeContract.read.encryptBundle([
      [formValues.height, formValues.transaction, formValues.profit],
      toHex(crypto.getRandomValues(new Uint8Array(32))),
    ]);

    setFormValues({
      height: formValues.height,
      transaction: "0x",
      profit: formValues.profit,
    });

    // TODO: separate function
    await kettle_advance(LocalConfig.KETTLE_RPC);

    const pubAbi = getAbiItem({
      abi: storeContract.abi,
      name: "publishEncryptedBundle",
    });
    const data = encodeFunctionData({
      abi: [pubAbi],
      args: [encryptedBundleBytes],
    });

    const resp = await kettle_execute(
      LocalConfig.KETTLE_RPC,
      storeContract.address,
      data.toString(),
    );

    updateConsoleLog(
      "Published the (encrypted) bundle: " +
        pretty_print_contract_call(pubAbi, [encryptedBundleBytes]),
    );
  };

  return (
    <div>
      <h2>Submit bundle</h2>
      <form onSubmit={handleSubmit} className="bundleform">
        <div style={{display: "inline-block"}}>
          <div style={{float: "left"}}>
            <label htmlFor="height">BlockHeight</label>
            <input
              type="number"
              id="height"
              name="height"
              value={formValues.height}
              onChange={handleChange}
            />
          </div>

          <div style={{float: "right"}}>
            <label htmlFor="profit">Profit</label>
            <input
              type="number"
              id="profit"
              name="profit"
              value={formValues.profit}
              onChange={handleChange}
            />
          </div>
        </div>

        <div>
          <div>
            <label htmlFor="transaction">Transaction</label>
            <textarea
              id="transaction"
              name="transaction"
              value={formValues.transaction}
              onChange={handleChange}
              rows="4"
              cols="50"
            ></textarea>
          </div>
        </div>

        <button type="submit">Submit</button>
      </form>
    </div>
  );
}

function StoreBundleFetcher({
  updateConsoleLog,
  suaveProvider,
  suaveWallet,
  storeContract,
}) {
  const [isModalOpen, setModalOpen] = useState(false);
  const [modalData, setModalData] = useState([]);
  const [formValues, setFormValues] = useState({
    height: "10",
  });

  const handleChange = (e) => {
    setFormValues({
      ...formValues,
      [e.target.name]: e.target.value,
    });
  };

  const handleSubmit = async (e) => {
    e.preventDefault();

    const fetchAbi = getAbiItem({
      abi: storeContract.abi,
      name: "dbg_getBundlesByHeight",
    });
    const data = encodeFunctionData({ abi: [fetchAbi], args: [formValues.height] });

    const resp = await kettle_execute(
      LocalConfig.KETTLE_RPC,
      storeContract.address,
      data.toString(),
    );

    const callLog = pretty_print_contract_call(fetchAbi, [formValues.height]);
    const executionResult = JSON.parse(resp);
    if (executionResult.Success === undefined) {
      updateConsoleLog(
        "Kettle refused to get bundles by height: " +
          callLog +
          log_font_color(
            "red",
            ' error: "' +
              format_revert_string(executionResult.Revert.output) +
              '"',
          ),
      );
      return false;
    }

    const decodedResult = decodeFunctionResult({
      abi: [fetchAbi],
      data: executionResult.Success.output.Call,
    });

    if (decodedResult == null) {
      throw new Error("unable to decode result");
    }

    updateConsoleLog(
      "Fetched "+decodedResult.length+" bundles targetting height " +formValues.height
    );

    setModalData(decodedResult.map(parseBundleBigints));
    setModalOpen(true);
  };

  return (
    <div>
      <form onSubmit={handleSubmit} className="bundleform"  style={{display: "inline-flex", margin: "0 auto"}}>
        <div>
          <div>
            <label htmlFor="height">BlockHeight</label>
            <input
              type="number"
              id="height"
              name="height"
              value={formValues.height}
              onChange={handleChange}
            />
          </div>
        </div>
        <button type="submit" style={{margin_left: "auto"}}>Fetch bundles by height</button>
      </form>
      <Modal
        hasCloseButton={false}
        isOpen={isModalOpen}
        onClose={() => { setModalOpen(false); }}
      >
        <h3>Bundles targetting block {formValues.height}</h3>
        <table className="bundleTable">
          <thead>
            <tr>
              <th>height</th>
              <th>transaction</th>
              <th>profit</th>
            </tr>
          </thead>
          <tbody>
            { modalData.map((b, i) => (
              <tr key={i}>
                <td>{b.height}</td>
                <td>{b.transaction}</td>
                <td>{b.profit}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Modal>
    </div>
  );
}

interface ModalProps {
  isOpen: boolean;
  hasCloseBtn?: boolean;
  onClose?: () => void;
  children: React.ReactNode;
};
const Modal: React.FC<MOdalProps> = ({ isOpen, hasCloseBtn, onClose, children }) => {
  const [isModalOpen, setModalOpen] = useState(isOpen);
  const modalRef = useRef<HTMLDialogElement | null>(null);

  useEffect(() => {
    setModalOpen(isOpen);
  }, [isOpen]);

  useEffect(() => {
    const modalElement = modalRef.current;
    if (modalElement) {
      if (isModalOpen) {
        modalElement.showModal();
      } else {
        modalElement.close();
      }
    }
  }, [isModalOpen]);

  const handleCloseModal = () => {
    if (onClose) {
      onClose();
    }
    setModalOpen(false);
  };

  const handleKeyDown = (event: React.KeyboardEvent<HTMLDialogElement>) => {
    if (event.key === "Escape") {
      handleCloseModal();
    }
  };

  return (
    <dialog ref={modalRef} onKeyDown={handleKeyDown}>
      {hasCloseBtn && (
        <button className="modal-close-btn" onClick={handleCloseModal}>
          Close
        </button>
      )}
      {children}
    </dialog>
  );
};

function BundleViewer({
  updateConsoleLog,
  suaveProvider,
  suaveWallet,
  storeContract,
}) {
  const [bundles, setBundles] = useState([]);
  const bundlesRef = useRef(bundles);

  function addBundle(bundle) {
    const newBundles = [...bundlesRef.current, bundle];
    bundlesRef.current = newBundles;
    setBundles(newBundles);
  }

  useEffect(() => {
    (async () => {
      for (;;) {
        await kettle_advance(LocalConfig.KETTLE_RPC);
        const subAbi = getAbiItem({
          abi: storeContract.abi,
          name: "subscribe",
        });
        const data = encodeFunctionData({ abi: [subAbi], args: [] });
        const resp = await kettle_execute(
          LocalConfig.KETTLE_RPC,
          storeContract.address,
          data.toString(),
        );

        const executionResult = JSON.parse(resp);
        if (executionResult.Success !== undefined) {
          updateConsoleLog("Subscribed messages");
          return;
        }

        await new Promise((resolve) => setTimeout(resolve, 1000));
      }
    })();
  }, [suaveProvider]);

  const isPollingRef = useRef(false);
  useEffect(() => {
    // There's probably a better solution
    if (isPollingRef.current) {
      return;
    }
    isPollingRef.current = true;

    /* TODO: make sure this is really called only once */
    (async () => {
      for (;;) {
        if (!(await pollMessages())) {
          await new Promise((resolve) => setTimeout(resolve, 1000));
        }
      }
    })();
  }, []);

  async function pollMessages() /* Returns whether we should poll for the next message imediatelly */ {
    // await kettle_advance(LocalConfig.KETTLE_RPC);
    const pollAbi = getAbiItem({
      abi: storeContract.abi,
      name: "pollAndReturnBundle",
    });
    const data = encodeFunctionData({ abi: [pollAbi], args: [] });

    const resp = await kettle_execute(
      LocalConfig.KETTLE_RPC,
      storeContract.address,
      data.toString(),
    );

    const callLog = pretty_print_contract_call(pollAbi, []);
    const executionResult = JSON.parse(resp);
    if (executionResult.Success === undefined) {
      updateConsoleLog(
        "Kettle refused to poll: " +
          callLog +
          log_font_color(
            "red",
            ' error: "' +
              format_revert_string(executionResult.Revert.output) +
              '"',
          ),
      );
      return false;
    }

    const decodedResult = decodeFunctionResult({
      abi: [pollAbi],
      data: executionResult.Success.output.Call,
    });

    if (decodedResult == null) {
      throw new Error("unable to decode result");
    }

    if (!decodedResult[0]) {
      return false;
    }

    if (!decodedResult[1]) {
      // TODO: unathenticated bundle
      return true;
    }

    const bundleDecorator = (i, v) => {
      if (i != 2) return v;
      return JSON.stringify(parseBundleBigints(v));
    };
    updateConsoleLog(
      "Bundle message received: " +
        callLog +
        " -> " +
        pretty_print_contract_result(
          pollAbi,
          executionResult.Success.output.Call,
          bundleDecorator,
        ),
    );

    const bundle = decodedResult[2];
    addBundle(parseBundleBigints(bundle));

    return true;
  }

  return (
    <>
      <h2>Bundles received</h2>
      <div style={{ height: "24em", overflowY: "scroll", width: "100%"}}>
        <table className="bundleTable">
          <thead>
            <tr>
              <th>height</th>
              <th>transaction</th>
              <th>profit</th>
            </tr>
          </thead>
          <tbody>
            {bundles.map((b, i) => (
              <tr key={i}>
                <td>{b.height}</td>
                <td>{b.transaction}</td>
                <td>{b.profit}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}

function ConsoleLogViewer({ consoleLog }) {
  return (
    <>
      <div
        className="textbox"
        dangerouslySetInnerHTML={{ __html: consoleLog }}
      ></div>
    </>
  );
}

function App() {
  const [consoleLog, updateConsoleLog] = ConsoleLog();
  const [suaveProvider, suaveWallet] = Provider(updateConsoleLog);
  const [isContractInitialized, storeContract] = ConnectStoreContract(
    suaveProvider,
    suaveWallet,
    updateConsoleLog,
  );

  async function onBundleSubmitted(bundle) {
    console.log(bundle);
  }

  return (
    <div style={{ height: "100%" }}>
      <div>
        <a href="https://www.flashbots.net" target="_blank">
          <img src={flashbotsLogo} className="logo" alt="Flashbots logo" />
        </a>
      </div>

      {!isContractInitialized && (
        <button
          onClick={async () => {
            if (isTimelockInitialized != true) {
              await checkTimelockIsInitialized(isTimelockInitialized);
            }
          }}
        >
          <div>Check if contract is initialized</div>
        </button>
      )}

      {isContractInitialized && (
        <div style={{ width: "100%" }}>
          <div style={{ float: "left", width: "50%", min_height: "fit-content" }}>
            <BundleSubmission
              updateConsoleLog={updateConsoleLog}
              suaveProvider={suaveProvider}
              suaveWallet={suaveWallet}
              storeContract={storeContract}
            />
            <br />
            <StoreBundleFetcher
              updateConsoleLog={updateConsoleLog}
              suaveProvider={suaveProvider}
              suaveWallet={suaveWallet}
              storeContract={storeContract}
            />
          </div>
          <div style={{ float: "right", width: "50%"}}>
            <BundleViewer
              updateConsoleLog={updateConsoleLog}
              suaveProvider={suaveProvider}
              suaveWallet={suaveWallet}
              storeContract={storeContract}
            />
          </div>
        </div>
      )}
        <div style={{ clear: "both"}}>
          <br />
          <br />
          <ConsoleLogViewer consoleLog={consoleLog} />
          <br />
          No Rigil money? Get some at{" "}
          <a href="https://faucet.rigil.suave.flashbots.net" target="_blank">
            the faucet
          </a>
        </div>
    </div>
  );
}

function assert(condition: unknown, msg?: string): asserts condition {
  if (condition === false) throw new Error(msg);
}

function parseBundleBigints(bundle) {
  return {
    height: bundle.height.toString(),
    transaction: bundle.transaction,
    profit: bundle.profit.toString(),
  };
}

export default App;
