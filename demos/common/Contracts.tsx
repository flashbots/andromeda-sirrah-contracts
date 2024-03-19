import { useEffect, useState, useRef } from "react";

import { getContract } from "viem";

import { format_explorer_link } from "./ConsoleLog";

export function ConnectContract(
  suaveProvider,
  suaveWallet,
  contract,
  addr,
  updateConsoleLog,
) {
  const [isInitialized, setIsInitialized] = useState<boolean | undefined>();
  const initRef = useRef(isInitialized); // For use in timeouts
  initRef.current = isInitialized;

  const [C, setC] = useState<any | undefined>();

  useEffect(() => {
    if (isInitialized) {
      return;
    }

    checkIsInitialized();
    const timerCheckIsInitialized = setInterval(async () => {
      await checkIsInitialized();
    }, 1000); // Update every second

    // Clean up the interval on component unmount
    return () => {
      clearInterval(timerCheckIsInitialized);
    };
  }, [C, isInitialized]);

  async function checkIsInitialized() {
    if (initRef.current) {
      return;
    }

    const isInitialized = await C?.read.isInitialized();
    if (isInitialized && !initRef.current) {
      updateConsoleLog("Contract is initialized properly");
      setIsInitialized(true);
      initRef.current = true;
    } else {
      console.log("Contract is still not initialized");
      setIsInitialized(false);
      initRef.current = false;
    }
  }

  useEffect(() => {
    if (suaveProvider == undefined || suaveWallet == undefined) {
      return;
    }
    // Create contract instance
    const contractInstance = getContract({
      address: addr,
      abi: contract.abi,
      client: {
        public: suaveProvider,
        wallet: suaveWallet,
      },
    });
    updateConsoleLog(
      "Using contract at " +
        format_explorer_link({ address: contractInstance.address }),
    );
    setC(contractInstance);
  }, [suaveProvider, suaveWallet]);

  return [isInitialized, C];
}
