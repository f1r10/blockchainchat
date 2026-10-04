// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * UsernameRegistry — Blockchain qatının yeganə funksiyası:
 * username rezervasiyası + public key commitment.
 * 
 * IP, PeerID, mesaj, chat history SAXLANILMIR.
 */
contract UsernameRegistry {
    struct UserRecord {
        bytes32 commitment;   // hash(username + salt + pubkey)
        uint256 registeredAt;
        bool exists;
    }

    mapping(bytes32 => UserRecord) private records; // key = keccak256(username)
    mapping(bytes32 => bytes32) private commitmentToUsername;

    uint256 public constant REGISTRATION_FEE = 0;   // testnet: pulsuz
    uint256 public epochNumber;
    bytes32 public registryRoot;

    event UsernameRegistered(bytes32 indexed usernameHash, bytes32 commitment, uint256 epoch);
    event UsernameUpdated(bytes32 indexed usernameHash, bytes32 newCommitment, uint256 epoch);
    event EpochAdvanced(uint256 newEpoch, bytes32 newRoot);

    constructor() {
        epochNumber = 1;
    }

    /**
     * @dev Username qeydiyyatı.
     * usernameHash = keccak256(abi.encodePacked(username))
     * commitment   = keccak256(abi.encodePacked(username, salt, publicKey))
     */
    function register(bytes32 usernameHash, bytes32 commitment) external {
        require(!records[usernameHash].exists, "Username taken");
        require(commitment != bytes32(0), "Empty commitment");

        records[usernameHash] = UserRecord({
            commitment: commitment,
            registeredAt: block.timestamp,
            exists: true
        });

        commitmentToUsername[commitment] = usernameHash;
        emit UsernameRegistered(usernameHash, commitment, epochNumber);
    }

    /**
     * @dev Key yeniləmə (ratchet rotation, prekey yeniləmə).
     */
    function updateCommitment(bytes32 usernameHash, bytes32 newCommitment) external {
        require(records[usernameHash].exists, "Username not found");
        require(newCommitment != bytes32(0), "Empty commitment");

        records[usernameHash].commitment = newCommitment;
        emit UsernameUpdated(usernameHash, newCommitment, epochNumber);
    }

    /**
     * @dev Mövcudluq yoxlaması.
     */
    function isRegistered(bytes32 usernameHash) external view returns (bool) {
        return records[usernameHash].exists;
    }

    /**
     * @dev Commitment əldə etmə (public key doğrulama üçün).
     */
    function getCommitment(bytes32 usernameHash) external view returns (bytes32, uint256) {
        require(records[usernameHash].exists, "Username not found");
        UserRecord memory r = records[usernameHash];
        return (r.commitment, r.registeredAt);
    }

    /**
     * @dev Registry root yeniləmə (epoch advance).
     * Production-da bu merkle tree root-u olacaq.
     */
    function advanceEpoch(bytes32 newRoot) external {
        epochNumber++;
        registryRoot = newRoot;
        emit EpochAdvanced(epochNumber, newRoot);
    }

    /**
     * @dev Mövcud epoch və registry state-i əldə etmə.
     */
    function getState() external view returns (uint256, bytes32) {
        return (epochNumber, registryRoot);
    }
}
