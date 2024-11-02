// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/console.sol";

library BlsSdk {
    using BN254 for BN254.G1Point;

    ///@notice the user of the library should initiate a storage variable that has been built on this struct
    struct State {
        mapping(address operatorAddress => bool exists) operatorExists;
        mapping(address operatorAddress => uint256 index) operatorIndex;
        address[] operatorAddresses;
        BN254.G1Point aggregatedG1Pubkey;
        mapping(address operator => BN254.G1Point) operatorG1Pubkey;
        BN254.G1Point[] allOperatorPubkeyG1;
    }

    ///@notice performs registration
    ///@param state the state in which registration will take place
    ///@param operator address of the operator that will be registered
    ///@param extraData an abi encoded bytes field that contains g1 pubkey, g2 pubkey, message hash and the signature
    function operatorRegistration(State storage state, address operator, bytes memory extraData, bytes32 msgHash)
        external
    {
        (BN254.G1Point memory g1Pubkey, BN254.G2Point memory g2Pubkey, BN254.G1Point memory sign) =
            abi.decode(extraData, (BN254.G1Point, BN254.G2Point, BN254.G1Point));
        if (state.operatorExists[operator]) revert OperatorAlreadyRegistered();
        state.operatorG1Pubkey[operator] = g1Pubkey;
        state.operatorAddresses.push(operator);
        state.operatorExists[operator] = true;
        state.operatorIndex[operator] = state.allOperatorPubkeyG1.length;
        state.allOperatorPubkeyG1.push(g1Pubkey);

        verifySignature(g1Pubkey, g2Pubkey, sign, msgHash);

        // adding key bls key to aggregated keys
        state.aggregatedG1Pubkey = state.aggregatedG1Pubkey.plus(g1Pubkey);
    }

    ///@notice performs registration
    ///@param state the state in which unregistration will take place
    ///@param operator address of operator that will be unregistered
    function operatorUnregistration(State storage state, address operator) external {
        if (operator != state.operatorAddresses[state.operatorIndex[operator]]) {
            revert OperatorAndIndexDontMatch();
        }
        if (!state.operatorExists[operator]) revert OperatorIsNotRegistered();
        uint256 operatorAddressesLength = state.operatorAddresses.length;

        // deleting the operator pubkey
        state.allOperatorPubkeyG1[state.operatorIndex[operator]] =
            state.allOperatorPubkeyG1[state.allOperatorPubkeyG1.length - 1];
        state.allOperatorPubkeyG1.pop();

        state.operatorAddresses[state.operatorIndex[operator]] = state.operatorAddresses[operatorAddressesLength - 1];
        state.operatorIndex[state.operatorAddresses[operatorAddressesLength - 1]] = state.operatorIndex[operator];
        state.operatorAddresses.pop();

        state.operatorExists[operator] = false;
        delete state.operatorIndex[operator];

        // removing bls key from aggregated keys
        state.aggregatedG1Pubkey = state.aggregatedG1Pubkey.plus(state.operatorG1Pubkey[operator].negate());
        delete state.operatorG1Pubkey[operator];
    }

    ///@notice checks whether the paring is successful. i.e. the signature is valid
    ///@param g1Key the public key on G1 field
    ///@param g2Key the public key on G2 field
    ///@param sign the signature on G1 field
    ///@param msgHash the message hash that has been signed
    function verifySignature(
        BN254.G1Point memory g1Key,
        BN254.G2Point memory g2Key,
        BN254.G1Point memory sign,
        bytes32 msgHash
    ) public view {
        uint256 alpha = uint256(
            keccak256(
                abi.encode(g1Key.X, g1Key.Y, g2Key.X[0], g2Key.X[1], g2Key.Y[0], g2Key.Y[1], sign.X, sign.Y, msgHash)
            )
        );
        (bool pairingSuccessful, bool signatureIsValid) = BN254.safePairing(
            sign.plus(g1Key.scalar_mul(alpha)),
            BN254.negGeneratorG2(),
            BN254.hashToG1(msgHash).plus(BN254.generatorG1().scalar_mul(alpha)),
            g2Key,
            120000
        );

        if (!pairingSuccessful) revert PairingNotSuccessful();
        if (!signatureIsValid) revert SignatureVerificationFailed();
    }

    /* ======= View Functions ======= */

    ///@notice responds with whether the operator is registered or not
    ///@param state the state in which the presence of operator will be checked
    ///@param operator address of operator whose registration status will be checked
    function isOperatorRegistered(State storage state, address operator) external view returns (bool) {
        return state.operatorExists[operator];
    }

    ///@notice returns an array of G1 public keys of all registered operators
    ///@param state the state that will be used for the retireval of G1 public keys
    function allOperatorsG1(State storage state) external view returns (BN254.G1Point[] memory) {
        BN254.G1Point[] memory operators = new BN254.G1Point[](state.allOperatorPubkeyG1.length);
        for (uint256 i = 0; i < state.allOperatorPubkeyG1.length; i++) {
            operators[i] = state.allOperatorPubkeyG1[i];
        }
        return operators;
    }

    /* ======= Errors ======= */
    error OperatorAlreadyRegistered();
    error OperatorAndIndexDontMatch();
    error OperatorIsNotRegistered();
    error SignatureVerificationFailed();
    error PairingNotSuccessful();
}

library BN254 {
    // modulus for the underlying field F_p of the elliptic curve
    uint256 internal constant FP_MODULUS = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
    // modulus for the underlying field F_r of the elliptic curve
    uint256 internal constant FR_MODULUS = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

    struct G1Point {
        uint256 X;
        uint256 Y;
    }

    // Encoding of field elements is: X[1] * i + X[0]
    struct G2Point {
        uint256[2] X;
        uint256[2] Y;
    }

    function generatorG1() internal pure returns (G1Point memory) {
        return G1Point(1, 2);
    }

    // generator of group G2
    /// @dev Generator point in F_q2 is of the form: (x0 + ix1, y0 + iy1).
    uint256 internal constant G2x1 = 11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 internal constant G2x0 = 10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 internal constant G2y1 = 4082367875863433681332203403145435568316851327593401208105741076214120093531;
    uint256 internal constant G2y0 = 8495653923123431417604973247489272438418190587263600148770280649306958101930;

    /// @notice returns the G2 generator
    /// @dev mind the ordering of the 1s and 0s!
    ///      this is because of the (unknown to us) convention used in the bn254 pairing precompile contract
    ///      "Elements a * i + b of F_p^2 are encoded as two elements of F_p, (a, b)."
    ///      https://github.com/ethereum/EIPs/blob/master/EIPS/eip-197.md#encoding
    function generatorG2() internal pure returns (G2Point memory) {
        return G2Point([G2x1, G2x0], [G2y1, G2y0]);
    }

    // negation of the generator of group G2
    /// @dev Generator point in F_q2 is of the form: (x0 + ix1, y0 + iy1).
    uint256 internal constant nG2x1 = 11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 internal constant nG2x0 = 10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 internal constant nG2y1 = 17805874995975841540914202342111839520379459829704422454583296818431106115052;
    uint256 internal constant nG2y0 = 13392588948715843804641432497768002650278120570034223513918757245338268106653;

    function negGeneratorG2() internal pure returns (G2Point memory) {
        return G2Point([nG2x1, nG2x0], [nG2y1, nG2y0]);
    }

    bytes32 internal constant powersOfTauMerkleRoot = 0x22c998e49752bbb1918ba87d6d59dd0e83620a311ba91dd4b2cc84990b31b56f;

    /**
     * @param p Some point in G1.
     * @return The negation of `p`, i.e. p.plus(p.negate()) should be zero.
     */
    function negate(G1Point memory p) internal pure returns (G1Point memory) {
        // The prime q in the base field F_q for G1
        if (p.X == 0 && p.Y == 0) {
            return G1Point(0, 0);
        } else {
            return G1Point(p.X, FP_MODULUS - (p.Y % FP_MODULUS));
        }
    }

    /**
     * @return r the sum of two points of G1
     */
    function plus(G1Point memory p1, G1Point memory p2) internal view returns (G1Point memory r) {
        uint256[4] memory input;
        input[0] = p1.X;
        input[1] = p1.Y;
        input[2] = p2.X;
        input[3] = p2.Y;
        bool success;

        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 6, input, 0x80, r, 0x40)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 { invalid() }
        }

        require(success, "ec-add-failed");
    }

    /**
     * @notice an optimized ecMul implementation that takes O(log_2(s)) ecAdds
     * @param p the point to multiply
     * @param s the scalar to multiply by
     * @dev this function is only safe to use if the scalar is 9 bits or less
     */
    function scalar_mul_tiny(BN254.G1Point memory p, uint16 s) internal view returns (BN254.G1Point memory) {
        require(s < 2 ** 9, "scalar-too-large");

        // if s is 1 return p
        if (s == 1) {
            return p;
        }

        // the accumulated product to return
        BN254.G1Point memory acc = BN254.G1Point(0, 0);
        // the 2^n*p to add to the accumulated product in each iteration
        BN254.G1Point memory p2n = p;
        // value of most significant bit
        uint16 m = 1;
        // index of most significant bit
        uint8 i = 0;

        //loop until we reach the most significant bit
        while (s >= m) {
            unchecked {
                // if the  current bit is 1, add the 2^n*p to the accumulated product
                if ((s >> i) & 1 == 1) {
                    acc = plus(acc, p2n);
                }
                // double the 2^n*p for the next iteration
                p2n = plus(p2n, p2n);

                // increment the index and double the value of the most significant bit
                m <<= 1;
                ++i;
            }
        }

        // return the accumulated product
        return acc;
    }

    /**
     * @return r the product of a point on G1 and a scalar, i.e.
     *         p == p.scalar_mul(1) and p.plus(p) == p.scalar_mul(2) for all
     *         points p.
     */
    function scalar_mul(G1Point memory p, uint256 s) internal view returns (G1Point memory r) {
        uint256[3] memory input;
        input[0] = p.X;
        input[1] = p.Y;
        input[2] = s;
        bool success;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 7, input, 0x60, r, 0x40)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 { invalid() }
        }
        require(success, "ec-mul-failed");
    }

    /**
     *  @return The result of computing the pairing check
     *         e(p1[0], p2[0]) *  .... * e(p1[n], p2[n]) == 1
     *         For example,
     *         pairing([P1(), P1().negate()], [P2(), P2()]) should return true.
     */
    function pairing(G1Point memory a1, G2Point memory a2, G1Point memory b1, G2Point memory b2)
        internal
        view
        returns (bool)
    {
        G1Point[2] memory p1 = [a1, b1];
        G2Point[2] memory p2 = [a2, b2];

        uint256[12] memory input;

        for (uint256 i = 0; i < 2; i++) {
            uint256 j = i * 6;
            input[j + 0] = p1[i].X;
            input[j + 1] = p1[i].Y;
            input[j + 2] = p2[i].X[0];
            input[j + 3] = p2[i].X[1];
            input[j + 4] = p2[i].Y[0];
            input[j + 5] = p2[i].Y[1];
        }

        for (uint256 i = 0; i < 12; i++) {
            console.logBytes32(bytes32(input[i]));
        }

        uint256[1] memory out;
        bool success;

        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 8, input, mul(12, 0x20), out, 0x20)
        }

        require(success, "pairing-opcode-failed");

        return out[0] != 0;
    }

    /**
     * @notice This function is functionally the same as pairing(), however it specifies a gas limit
     *         the user can set, as a precompile may use the entire gas budget if it reverts.
     */
    function safePairing(G1Point memory a1, G2Point memory a2, G1Point memory b1, G2Point memory b2, uint256 pairingGas)
        internal
        view
        returns (bool, bool)
    {
        G1Point[2] memory p1 = [a1, b1];
        G2Point[2] memory p2 = [a2, b2];

        uint256[12] memory input;

        for (uint256 i = 0; i < 2; i++) {
            uint256 j = i * 6;
            input[j + 0] = p1[i].X;
            input[j + 1] = p1[i].Y;
            input[j + 2] = p2[i].X[0];
            input[j + 3] = p2[i].X[1];
            input[j + 4] = p2[i].Y[0];
            input[j + 5] = p2[i].Y[1];
        }

        uint256[1] memory out;
        bool success;

        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(pairingGas, 8, input, mul(12, 0x20), out, 0x20)
        }

        //Out is the output of the pairing precompile, either 0 or 1 based on whether the two pairings are equal.
        //Success is true if the precompile actually goes through (aka all inputs are valid)

        return (success, out[0] != 0);
    }

    /// @return hashedG1 the keccak256 hash of the G1 Point
    /// @dev used for BLS signatures
    function hashG1Point(BN254.G1Point memory pk) internal pure returns (bytes32 hashedG1) {
        assembly {
            mstore(0, mload(pk))
            mstore(0x20, mload(add(0x20, pk)))
            hashedG1 := keccak256(0, 0x40)
        }
    }

    /// @return the keccak256 hash of the G2 Point
    /// @dev used for BLS signatures
    function hashG2Point(BN254.G2Point memory pk) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(pk.X[0], pk.X[1], pk.Y[0], pk.Y[1]));
    }

    /**
     * @notice adapted from https://github.com/HarryR/solcrypto/blob/master/contracts/altbn128.sol
     */
    function hashToG1(bytes32 _x) internal view returns (G1Point memory) {
        uint256 beta = 0;
        uint256 y = 0;

        uint256 x = uint256(_x) % FP_MODULUS;

        while (true) {
            (beta, y) = findYFromX(x);

            // y^2 == beta
            if (beta == mulmod(y, y, FP_MODULUS)) {
                return G1Point(x, y);
            }

            x = addmod(x, 1, FP_MODULUS);
        }
        return G1Point(0, 0);
    }

    /**
     * Given X, find Y
     *
     *   where y = sqrt(x^3 + b)
     *
     * Returns: (x^3 + b), y
     */
    function findYFromX(uint256 x) internal view returns (uint256, uint256) {
        // beta = (x^3 + b) % p
        uint256 beta = addmod(mulmod(mulmod(x, x, FP_MODULUS), x, FP_MODULUS), 3, FP_MODULUS);

        // y^2 = x^3 + b
        // this acts like: y = sqrt(beta) = beta^((p+1) / 4)
        uint256 y = expMod(beta, 0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52, FP_MODULUS);

        return (beta, y);
    }

    function expMod(uint256 _base, uint256 _exponent, uint256 _modulus) internal view returns (uint256 retval) {
        bool success;
        uint256[1] memory output;
        uint256[6] memory input;
        input[0] = 0x20; // baseLen = new(big.Int).SetBytes(getData(input, 0, 32))
        input[1] = 0x20; // expLen  = new(big.Int).SetBytes(getData(input, 32, 32))
        input[2] = 0x20; // modLen  = new(big.Int).SetBytes(getData(input, 64, 32))
        input[3] = _base;
        input[4] = _exponent;
        input[5] = _modulus;
        assembly {
            success := staticcall(sub(gas(), 2000), 5, input, 0xc0, output, 0x20)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 { invalid() }
        }
        require(success, "BN254.expMod: call failure");
        return output[0];
    }
}
