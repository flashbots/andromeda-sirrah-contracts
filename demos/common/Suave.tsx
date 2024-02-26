import { useEffect, useState } from "react";

import {
  getContract,
  createPublicClient,
  createWalletClient,
  custom,
  http,
  defineChain,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

import * as LocalConfig from "../../deployment.json";

import {
  log_font_color,
  format_explorer_link,
  format_revert_string,
} from "./ConsoleLog";

export function Provider(updateConsoleLog) {
  const [suaveProvider, setSuaveProvider] = useState<any>();
  const [suaveWallet, setSuaveWallet] = useState<any>();

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

    updateConsoleLog(
      "Using Metamask with account " +
        format_explorer_link({ address: account }),
    );
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

      updateConsoleLog(
        "Using local private key for " +
          format_explorer_link({ address: account.address }),
      );
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

  return [suaveProvider, suaveWallet];
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
