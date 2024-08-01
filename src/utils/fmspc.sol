pragma solidity ^0.8.0;

import {V3Struct} from "../../lib/automata-dcap-v3-attestation/contracts/lib/QuoteV3Auth/V3Struct.sol";
import {V3Parser} from "../../lib/automata-dcap-v3-attestation/contracts/lib/QuoteV3Auth/V3Parser.sol";
import {PEMCertChainLib} from "../../lib/automata-dcap-v3-attestation/contracts/lib/PEMCertChainLib.sol";
import {IPEMCertChainLib} from "../../lib/automata-dcap-v3-attestation/contracts/lib/interfaces/IPEMCertChainLib.sol";

// Internal Libraries
import {Base64} from "solady/src/Milady.sol";

contract FmspcParser {
    IPEMCertChainLib public immutable pemCertLib;

    constructor() {
        pemCertLib = new PEMCertChainLib();
    }

    function extract_fmspc_from_bootstrap(address, bytes calldata att) public returns (bool, string memory) {
        return extract_fmspc(att);
    }

    function extract_fmspc(bytes calldata quote) public returns (bool, string memory) {
        (bool successful,,,, V3Struct.ECDSAQuoteV3AuthData memory authDataV3) = V3Parser.parseInput(quote);
        if (!successful) {
            return (false, "could not parse quote");
        }

        IPEMCertChainLib.ECSha256Certificate[] memory parsedQuoteCerts;
        {
            // 660k gas
            (bool certParsedSuccessfully, bytes[] memory quoteCerts) =
                pemCertLib.splitCertificateChain(authDataV3.certification.certData, 3);
            if (!certParsedSuccessfully) {
                return (false, "could not parse cert");
            }

            // 536k gas
            parsedQuoteCerts = new IPEMCertChainLib.ECSha256Certificate[](3);
            for (uint256 i = 0; i < 3; i++) {
                quoteCerts[i] = Base64.decode(string(quoteCerts[i]));
                bool isPckCert = i == 0; // additional parsing for PCKCert
                bool certDecodedSuccessfully;
                (certDecodedSuccessfully, parsedQuoteCerts[i]) = pemCertLib.decodeCert(quoteCerts[i], isPckCert);
                if (!certDecodedSuccessfully) {
                    return (false, "could not decode cert");
                }
            }
        }

        string memory parsedFmspc = parsedQuoteCerts[0].pck.sgxExtension.fmspc;
        return (true, parsedFmspc);
    }
}
