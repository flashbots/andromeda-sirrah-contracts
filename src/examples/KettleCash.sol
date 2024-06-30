pragma solidity ^0.8.13;

import "../crypto/secp256k1.sol";
import "../crypto/encryption.sol";

import "../KeyManager.sol";
import "../IAndromeda.sol";

struct Check {
    // address sender; // User account of sender
    // address issuer; // Kettle of sender
    uint amount;
    address recipient; // User account of recipient
    address kettle;    // Recipient's Kettle
    bytes32 nonce;     // Unique tag
    bytes att;         // Signed by issuer
}

contract KettleCash {
    KeyManager_v0 keymgr;
    IAndromeda Suave;

    ///////////////////////////////////////
    // Onchain functions
    ///////////////////////////////////////
    
    constructor(KeyManager_v0 _keymgr) {
        keymgr = _keymgr;
	Suave = _keymgr.Suave();
    }

    // On-Chain deposit to a Kettle
    // This produces an off-chain check with an empty attestation.
    // This can be deposited at the specified kettle.
    event Deposit(address depositor, uint amt, address kettle);
    mapping (bytes32 serial => bool) deposits;
    uint deposit_counter;
    function onchain_Deposit(address kettle) public payable
    returns(Check memory c) {
	c.amount = msg.value;
	c.recipient = msg.sender;
	c.kettle = kettle;
	c.nonce = bytes32(deposit_counter);
	deposits[CheckSerial(c)] = true;
	deposit_counter += 1;
	emit Deposit(msg.sender, msg.value, kettle);
    }

    // Cash an on-chain check
    mapping (bytes32 serial => bool) public cashed;
    event Withdrawal(bytes32 serial, Check check);
    function onchain_Withdraw(Check memory check) public {
	bytes32 serial = CheckSerial(check);
	
	// A withdrawal check has check.kettle == 0
	require(check.kettle == address(0));

	// Only cash a check once
	require(!cashed[serial]);
	
	// Must verify under this contract
	require(keymgr.verify(address(this), serial, check.att));

	// Carry out the transfer
	cashed[serial] = true;
	payable(check.recipient).transfer(check.amount);
    }

    ///////////////////////////////////////
    // CoProcessor functions for a Kettle
    ///////////////////////////////////////

    function offchain_ThisKettle() public returns (address) {
	// Must be registered with key manager
	require(keymgr.derivedPriv() != bytes32(0));

	// Store our volatile address
	address addr = address(bytes20(Suave.volatileGet(bytes32("_this_kettle"))));
	if (addr == address(0)) {
	    addr = address(bytes20(Suave.localRandom()));
	    Suave.volatileSet(bytes32("_this_kettle"), bytes32(abi.encodePacked(addr)));
	}
	
	return addr;
    }

    function CheckSerial(Check memory check) public pure returns(bytes32){
	// Serialize everything except the signature
	Check memory c;
	//c.sender    = check.sender;
	c.amount    = check.amount;
	c.recipient = check.recipient;
	c.kettle    = check.kettle;
	c.nonce     = check.nonce;
	c.att       = bytes(""); 
	return keccak256(abi.encode(c));
    }

    function _IsSpent(Check memory check) public returns(bool) {
	// Only meaningful if it belongs to this kettle ours
	require(offchain_ThisKettle() == check.kettle);
	bytes32 serial = CheckSerial(check);
	bytes32 key = keccak256(abi.encodePacked("cashed",serial));
	return Suave.volatileGet(key) != bytes32(0);
    }

    // Query the volatile accountBalance
    function offchain_QueryBalance(address depositor) public returns(uint) {
	// Read the balance from volatile memory
	bytes32 key = keccak256(abi.encodePacked("balance",depositor));
	return uint(Suave.volatileGet(key));
    }

    function _WriteBalance(address depositor, uint balance) internal {
	// Write the balance to volatile memory
	bytes32 key = keccak256(abi.encodePacked("balance",depositor));
	Suave.volatileSet(key, bytes32(balance));
    }
    
    // Deposit a check
    function offchain_DepositCheck(Check memory check) public {
	// Only cash checks pointing to this kettle
	require(offchain_ThisKettle() == check.kettle);

	// If a deposit, needs to be finalized on-chain
	if (check.att.length == 0) {
	    require(deposits[CheckSerial(check)]);
	} else {
	    // Otherwise needs need to have a valid attestation
	    require(keymgr.verify(address(this), CheckSerial(check),
				  check.att));
	}
	
	// Only valid if signed by a kettle
	bytes32 serial = CheckSerial(check);
	bytes32 key = keccak256(abi.encodePacked("cashed",serial));
	require(!_IsSpent(check));

	// Mark the check as spent, then update balance
	uint balance = offchain_QueryBalance(check.recipient);	
	Suave.volatileSet(key, bytes32("voidvoidvoidvoidvoidvoidvoidvoid"));
	_WriteBalance(check.recipient, balance + check.amount);
    }

    // Issue a check
    function offchain_IssueCheck(address recipient, address kettle, uint amount) public returns (Check memory) {
	// Verify the balance is OK
	uint balance = offchain_QueryBalance(msg.sender);
	require(balance >= amount);

	// Define the check
	Check memory c;
	c.amount = amount;
	c.recipient = recipient;
	c.kettle = kettle;
	c.nonce = Suave.localRandom();

	// Sign the check
	c.att = keymgr.attest(CheckSerial(c));
	require(keymgr.verify(address(this), CheckSerial(c), c.att));

	// Update the balance and return the Check
	_WriteBalance(msg.sender, balance - amount);
	return c;
    }
}
