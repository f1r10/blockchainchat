// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CommitmentRegistry
 * @notice Decentralized, zero-metadata Username Commitment & Rendezvous Locator Registry.
 * @dev Hyper-optimized EVM registry storing mapping of `Hash(Username + Salt)` to owner address and rendezvous pointer.
 */
contract CommitmentRegistry {
    struct Registration {
        address owner;
        string rendezvousPointer;
    }

    /// @notice Mapping from username commitment hash to registration record
    mapping(bytes32 => Registration) private _registrations;

    /// @notice Emitted when a new username commitment is registered
    event CommitmentRegistered(bytes32 indexed commitment, address indexed owner, string rendezvousPointer);
    
    /// @notice Emitted when a rendezvous pointer is updated by its owner
    event RendezvousPointerUpdated(bytes32 indexed commitment, address indexed owner, string newRendezvousPointer);

    /// @dev Error thrown when attempting to register an already claimed commitment
    error AlreadyRegistered();
    /// @dev Error thrown when an unauthorized caller attempts to update a commitment
    error Unauthorized();
    /// @dev Error thrown when commitment hash is empty
    error InvalidCommitment();

    /**
     * @notice Registers a new username commitment with an initial rendezvous pointer.
     * @param commitment The bytes32 hash Hash(Username + Salt).
     * @param rendezvousPointer The DHT/OPRF pointer string referencing the user's Prekey bundle & SURBs.
     */
    function register(bytes32 commitment, string calldata rendezvousPointer) external {
        if (commitment == bytes32(0)) revert InvalidCommitment();
        if (_registrations[commitment].owner != address(0)) revert AlreadyRegistered();

        _registrations[commitment] = Registration({
            owner: msg.sender,
            rendezvousPointer: rendezvousPointer
        });

        emit CommitmentRegistered(commitment, msg.sender, rendezvousPointer);
    }

    /**
     * @notice Updates the rendezvous pointer for an existing username commitment.
     * @dev Only the original registrant (`msg.sender`) can call this function.
     * @param commitment The bytes32 hash Hash(Username + Salt).
     * @param newRendezvousPointer The new DHT/OPRF locator string.
     */
    function updateRendezvousPointer(bytes32 commitment, string calldata newRendezvousPointer) external {
        Registration storage record = _registrations[commitment];
        if (record.owner == address(0)) revert InvalidCommitment();
        if (record.owner != msg.sender) revert Unauthorized();

        record.rendezvousPointer = newRendezvousPointer;

        emit RendezvousPointerUpdated(commitment, msg.sender, newRendezvousPointer);
    }

    /**
     * @notice Resolves a username commitment to its owner and current rendezvous pointer.
     * @param commitment The bytes32 hash Hash(Username + Salt).
     * @return owner The address of the commitment owner.
     * @return rendezvousPointer The active rendezvous locator.
     */
    function getRegistration(bytes32 commitment) external view returns (address owner, string memory rendezvousPointer) {
        Registration memory record = _registrations[commitment];
        if (record.owner == address(0)) revert InvalidCommitment();
        return (record.owner, record.rendezvousPointer);
    }

    /**
     * @notice Returns whether a username commitment has already been registered.
     * @param commitment The bytes32 hash Hash(Username + Salt).
     */
    function isRegistered(bytes32 commitment) external view returns (bool) {
        return _registrations[commitment].owner != address(0);
    }
}
