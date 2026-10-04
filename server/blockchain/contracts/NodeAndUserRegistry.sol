// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NodeAndUserRegistry
 * @notice Tam mərkəzsiz P2P Discovery və Username Commitment Kontraktı.
 * 
 * Heç bir IP, mesaj və ya chat metadata-sı saxlanmır.
 * Yalnız:
 * 1. Relay və Mailbox node-larının şəbəkə elanları (IP:Port)
 * 2. İstifadəçi username commitment-ləri (ZKP / Hash formatında)
 */
contract NodeAndUserRegistry {
    // ── NODE DISCOVERY ───────────────────────────────────────────
    struct NodeInfo {
        string endpoint;     // Məsələn: "http://192.168.1.102:3000"
        bytes32 pubkey;      // Node-un şifrələmə açarı
        uint256 registeredAt;
        bool exists;
    }

    NodeInfo[] public relays;
    NodeInfo[] public mailboxes;

    mapping(string => bool) private relayEndpoints;
    mapping(string => bool) private mailboxEndpoints;

    event RelayRegistered(string endpoint, bytes32 pubkey);
    event MailboxRegistered(string endpoint, bytes32 pubkey);

    function registerRelay(string calldata endpoint, bytes32 pubkey) external {
        require(!relayEndpoints[endpoint], "Relay already registered");
        relayEndpoints[endpoint] = true;
        relays.push(NodeInfo({
            endpoint: endpoint,
            pubkey: pubkey,
            registeredAt: block.timestamp,
            exists: true
        }));
        emit RelayRegistered(endpoint, pubkey);
    }

    function registerMailbox(string calldata endpoint, bytes32 pubkey) external {
        require(!mailboxEndpoints[endpoint], "Mailbox already registered");
        mailboxEndpoints[endpoint] = true;
        mailboxes.push(NodeInfo({
            endpoint: endpoint,
            pubkey: pubkey,
            registeredAt: block.timestamp,
            exists: true
        }));
        emit MailboxRegistered(endpoint, pubkey);
    }

    function getRelays() external view returns (NodeInfo[] memory) {
        return relays;
    }

    function getMailboxes() external view returns (NodeInfo[] memory) {
        return mailboxes;
    }

    // ── USERNAME COMMITMENTS ─────────────────────────────────────
    struct UserRecord {
        bytes32 commitment;   // keccak256(username + salt + identityKey)
        bytes32 prekeyBundle; // Ephemeral public prekey for X3DH / Ratchet init
        uint256 registeredAt;
        bool exists;
    }

    // usernameHash => UserRecord
    mapping(bytes32 => UserRecord) private users;

    event UserRegistered(bytes32 indexed usernameHash, bytes32 commitment, bytes32 prekeyBundle);
    event UserPrekeyRotated(bytes32 indexed usernameHash, bytes32 newPrekeyBundle);

    function registerUser(
        bytes32 usernameHash,
        bytes32 commitment,
        bytes32 prekeyBundle
    ) external {
        require(!users[usernameHash].exists, "Username already claimed");
        require(commitment != bytes32(0), "Invalid commitment");

        users[usernameHash] = UserRecord({
            commitment: commitment,
            prekeyBundle: prekeyBundle,
            registeredAt: block.timestamp,
            exists: true
        });

        emit UserRegistered(usernameHash, commitment, prekeyBundle);
    }

    function rotatePrekey(bytes32 usernameHash, bytes32 newPrekeyBundle) external {
        require(users[usernameHash].exists, "User not found");
        users[usernameHash].prekeyBundle = newPrekeyBundle;
        emit UserPrekeyRotated(usernameHash, newPrekeyBundle);
    }

    function getUser(bytes32 usernameHash) external view returns (bytes32 commitment, bytes32 prekeyBundle, uint256 registeredAt) {
        require(users[usernameHash].exists, "User not found");
        UserRecord memory u = users[usernameHash];
        return (u.commitment, u.prekeyBundle, u.registeredAt);
    }

    function isUserRegistered(bytes32 usernameHash) external view returns (bool) {
        return users[usernameHash].exists;
    }
}
