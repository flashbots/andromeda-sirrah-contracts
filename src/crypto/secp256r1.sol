pragma solidity ^0.8.0;

library Secp256r1 {
    address internal constant ECMUL_ADDR = 0x0000000000000000000000000000000000060700;
    uint256 internal constant ORDER = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551;
    uint256 internal constant G_X = 0x6b17d1f2_e12c4247_f8bce6e5_63a440f2_77037d81_2deb33a0_f4a13945_d898c296;
    uint256 internal constant G_Y = 0x4fe342e2_fe1a7f9b_8ee7eb4a_7c0f9e16_2bce3357_6b315ece_cbb64068_37bf51f5;

    struct Point {
        uint256 x;
        uint256 y;
    }

    function isScalar(uint256 scalar) internal pure returns (bool) {
        return scalar > 0 && scalar < ORDER;
    }

    function publicKey(uint256 sk) internal view returns (Point memory) {
        return ecmul(G_X, G_Y, sk);
    }

    function encodePkcs8Der(uint256 sk, Point memory pk) internal pure returns (bytes memory) {
        // PrivateKeyInfo ::= SEQUENCE {
        //   version                   Version,
        //   privateKeyAlgorithm       AlgorithmIdentifier,
        //   privateKey                OCTET STRING,
        //   attributes           [0]  IMPLICIT Attributes OPTIONAL }
        //
        // 30 81 87         ; SEQUENCE (0x87 bytes)
        //    02 01 00       ; INTEGER (0)
        //    30 13          ; SEQUENCE (0x13 bytes)
        //       06 07       ; OBJECT IDENTIFIER (ecPublicKey)
        //          2A 86 48 CE 3D 02 01
        //       06 08       ; OBJECT IDENTIFIER (prime256v1)
        //          2A 86 48 CE 3D 03 01 07
        //    04 6d          ; OCTET STRING (0x6d bytes)
        //       30 6b       ; SEQUENCE (0x6b bytes)
        //          02 01 01 ; INTEGER (1)
        //          04 20    ; OCTET STRING (32 bytes)
        //             <32 byte private key>
        //          a1 44    ; Attribute (0x44 bytes)
        //          03 42    ; BIT STRING (0x42 bytes)
        //             00 <sec1 encoded public key>
        return bytes.concat(
            hex"308187020100301306072a8648ce3d020106082a8648ce3d030107046d306b0201010420",
            bytes32(sk),
            hex"a14403420004",
            bytes32(pk.x),
            bytes32(pk.y)
        );
    }

    function ecmul(uint256 x, uint256 y, uint256 s) internal view returns (Point memory) {
        (bool success, bytes memory result) = ECMUL_ADDR.staticcall(abi.encode(x, y, s));
        require(success);
        return abi.decode(result, (Point));
    }
}
