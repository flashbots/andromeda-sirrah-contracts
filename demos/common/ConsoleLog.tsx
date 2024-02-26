import { useEffect, useState } from "react";

import { decodeFunctionResult, decodeFunctionData } from "viem";

export function ConsoleLog() {
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

  return [consoleLog, updateConsoleLog];
}

export function log_font_color(color: string, str: string) {
  return '<font color="' + color + '">' + str + "</font>";
}

export function format_explorer_link(target: {
  address?: string;
  tx?: string;
}) {
  const link =
    target.address !== undefined
      ? "https://explorer.rigil.suave.flashbots.net/address/" + target.address
      : "https://explorer.rigil.suave.flashbots.net/tx/" + target.tx;
  const value = target.address !== undefined ? target.address : target.tx;
  return '<a target="_blank" href=' + link + ">" + value + "</a>";
}

export function format_revert_string(rawOutput: "0x{string}") {
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

export function pretty_print_contract_call(abi, inputs) {
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

export function pretty_print_contract_result(
  methodAbi,
  rawOutput: "0x{string}",
  decorator: (k: int | string, v: any) => string,
) {
  if (decorator === undefined) {
    decorator = (_k, x) => x;
  }

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
    res += methodAbi.outputs[i].type + " " + methodAbi.outputs[i].name + ": ";

    if (Array.isArray(decodedResult)) {
      res += decorator(i, decodedResult[i]);
    } else {
      res += decorator(
        methodAbi.outputs[i].name,
        decodedResult[methodAbi.outputs[i].name],
      );
    }

    if (i + 1 != methodAbi.outputs.length) {
      res += ", ";
    }
  }

  res += "]";
  return res;
}

function assert(condition: unknown, msg?: string): asserts condition {
  if (condition === false) throw new Error(msg);
}
