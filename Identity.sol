pragma solidity ^0.4.18;

import "./ERC725.sol";
import "./ERC735.sol";

contract Identity is ERC725, ERC735 {
    uint256 executionNonce;
    bytes32 claimId;

    struct Execution {
        address to;
        uint256 value;
        bytes data;
        bool approved;
        bool executed;
    }

    mapping (bytes32 => Key) keys;
    mapping (uint256 => bytes32[]) keysByPurpose;
    mapping (uint256 => Execution) executions;
    mapping (bytes32 => Claim) claims;
    mapping (uint256 => bytes32[]) claimsByType;
    
    modifier managerOnly {
        require(keys[keccak256(msg.sender)].purpose == MANAGEMENT_KEY);
        _;
    }

    modifier managerOrSelf {
        require(keys[keccak256(msg.sender)].purpose == MANAGEMENT_KEY || msg.sender == address(this));
        _;
    }

    modifier actorOnly {
        require(keys[keccak256(msg.sender)].purpose == ACTION_KEY);
        _;
    }

    modifier claimSignerOnly {
        require(keys[keccak256(msg.sender)].purpose == CLAIM_SIGNER_KEY);
        _;
    }

    event ExecutionFailed(uint256 indexed executionId, address indexed to, uint256 indexed value, bytes data);

    function Identity() public {
        bytes32 key = keccak256(msg.sender);
        
        keys[key].key = key;
        keys[key].purpose = MANAGEMENT_KEY;
        keys[key].keyType = ECDSA_TYPE;
        
        keysByPurpose[MANAGEMENT_KEY].push(key);
        
        emit KeyAdded(key, keys[key].purpose, MANAGEMENT_KEY);
    }

    function getKey(bytes32 _key) public constant returns(uint256 purpose, uint256 keyType, bytes32 key) {
        return (keys[_key].purpose, keys[_key].keyType, keys[_key].key);
    }

    function getKeyPurpose(bytes32 _key) public constant returns(uint256 purpose) {
        return (keys[_key].purpose);
    }

    function getKeysByPurpose(uint256 _purpose) public constant returns(bytes32[] _keys) {
        return keysByPurpose[_purpose];
    }

    function addKey(bytes32 _key, uint256 _purpose, uint256 _type) public managerOrSelf returns (bool success) {
        require(keys[_key].key != _key);

        keys[_key].key = _key;
        keys[_key].purpose = _purpose;
        keys[_key].keyType = _type;

        keysByPurpose[_purpose].push(_key);

        emit KeyAdded(_key, _purpose, _type);

        return true;
    }
    
    function removeKey(bytes32 _key) public managerOrSelf returns (bool success) {
        require(keys[_key].key == _key);
        
        emit KeyRemoved(keys[_key].key, keys[_key].purpose, keys[_key].keyType);

        delete keys[_key];

        return true;
    }
    
    function execute(address _to, uint256 _value, bytes _data) public returns (uint256 executionId) {
        require(keys[keccak256(msg.sender)].purpose == MANAGEMENT_KEY || keys[keccak256(msg.sender)].purpose == ACTION_KEY);
        require(!executions[executionNonce].executed);
        
        executions[executionNonce].to = _to;
        executions[executionNonce].value = _value;
        executions[executionNonce].data = _data;

        emit ExecutionRequested(executionNonce, _to, _value, _data);

        if (keys[keccak256(msg.sender)].purpose == MANAGEMENT_KEY || keys[keccak256(msg.sender)].purpose == ACTION_KEY) {
            approve(executionNonce, true);
        }

        executionNonce++; //increase for new id
        
        return executionNonce - 1; //minus 1 for current id
    }

    function approve(uint256 _id, bool _approve) public managerOnly returns (bool success) {
        emit Approved(_id, _approve);

        if (!_approve) {
            executions[_id].approved = false;
            return true;
        }

        executions[_id].approved = true;
        
        success = executions[_id].to.call(executions[_id].data);
        
        if (success) {
            executions[_id].executed = true;
            
            emit Executed(
                _id,
                executions[_id].to,
                executions[_id].value,
                executions[_id].data
            );
            
            return;
        } else {
            emit ExecutionFailed(
                _id,
                executions[_id].to,
                executions[_id].value,
                executions[_id].data
            );
            
            return;
        }

        return true;
    }

    function addClaim(uint256 _claimType, uint256 _scheme, address issuer, bytes _signature, bytes32 _data, string _uri) public claimSignerOnly returns (bytes32 claimRequestId) {
        claimId = keccak256(issuer, _claimType);

        if (claims[claimId].issuer != issuer) {
            claimsByType[_claimType].push(claimId);
        }

        claims[claimId].claimType = _claimType;
        claims[claimId].scheme = _scheme;
        claims[claimId].issuer = issuer;
        claims[claimId].signature = _signature;
        claims[claimId].data = _data;
        claims[claimId].uri = _uri;

        emit ClaimAdded(claimId, _claimType, _scheme, issuer, _signature, _data, _uri);

        return claimId;
    }

    function removeClaim(bytes32 _claimId) public returns (bool success) {
        require(
            msg.sender == claims[_claimId].issuer ||
            keys[keccak256(msg.sender)].purpose == MANAGEMENT_KEY ||
            msg.sender == address(this)
        );

        emit ClaimRemoved(
            _claimId,
            claims[_claimId].claimType,
            claims[_claimId].scheme,
            claims[_claimId].issuer,
            claims[_claimId].signature,
            claims[_claimId].data,
            claims[_claimId].uri
        );

        delete claims[_claimId];
        
        return true;
    }

    function getClaim(bytes32 _claimId) public constant returns(uint256 claimType, uint256 scheme, address issuer, bytes signature, bytes32 data, string uri) {
        return (
            claims[_claimId].claimType,
            claims[_claimId].scheme,
            claims[_claimId].issuer,
            claims[_claimId].signature,
            claims[_claimId].data,
            claims[_claimId].uri
        );
    }

    function getClaimIdsByType(uint256 _claimType) public constant returns(bytes32[] claimIds) {
        return claimsByType[_claimType];
    }
}