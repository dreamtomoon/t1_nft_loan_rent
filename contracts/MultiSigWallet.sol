// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract MultiSigWallet is ReentrancyGuard {
    using Counters for Counters.Counter;
    event Deposit(address indexed sender, uint256 amount, uint256 balance);
    event SubmitTransaction(
        address indexed signer,
        uint256 indexed txIndex,
        address indexed to,
        uint256 value,
        bytes data
    );

    address[] private signers;
    mapping(address => bool) public isSigner;
    uint256 public numConfirmationsRequired;

    // mapping from tx index => signer => bool
    mapping(uint256 => mapping(address => bool)) public isConfirmed;
    Counters.Counter private txIds;

    modifier onlySigner() {
        require(isSigner[msg.sender], "not signer");
        _;
    }

    constructor(address[] memory _signers, uint256 _numConfirmationsRequired) {
        require(_signers.length > 0, "signers required");
        require(
            _numConfirmationsRequired > 0 && _numConfirmationsRequired <= _signers.length,
            "invalid number of required confirmations"
        );

        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];

            require(signer != address(0), "invalid signer");
            require(!isSigner[signer], "signer not unique");

            isSigner[signer] = true;
            signers.push(signer);
        }

        numConfirmationsRequired = _numConfirmationsRequired;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    function submitTransaction(
        address _to,
        uint256 _value,
        bytes memory _data,
        bytes32[] memory rs,
        bytes32[] memory ss,
        uint8[] memory vs
    ) external payable onlySigner nonReentrant {
        require(_to != address(0), "ZERO Address");
        require(rs.length == ss.length && ss.length == vs.length, "Signaure lengths should be same");
        uint256 sigLength = rs.length;
        require(sigLength >= numConfirmationsRequired, "Less than needed required confirmations");
        if (_value > 0) {
            require(msg.value == _value, "Should send value");
        }
        uint256 ii;
        uint256 txIdx = txIds.current();
        for (ii = 0; ii < sigLength; ii++) {
            address _signer = _getSigner(_to, _value, _data, rs[ii], ss[ii], vs[ii]);
            require(
                isSigner[_signer] && !isConfirmed[txIdx][_signer],
                "Not signer or duplicated signer for this transaction"
            );
            isConfirmed[txIdx][_signer] = true;
        }
        (bool success, ) = _to.call{value: _value}(_data);
        require(success, "tx failed");

        emit SubmitTransaction(msg.sender, txIdx, _to, _value, _data);
        txIds.increment();
    }

    function _getSigner(
        address _to,
        uint256 _value,
        bytes memory _data,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) private pure returns (address) {
        bytes32 msgHash = keccak256(abi.encodePacked(_to, _value, _data));
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        address recoveredAddress = ecrecover(digest, v, r, s);
        return recoveredAddress;
    }

    function getSigners() external view returns (address[] memory) {
        return signers;
    }

    function getTransactionCount() external view returns (uint256) {
        return txIds.current();
    }
}
