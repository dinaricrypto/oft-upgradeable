// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import {
    ILayerZeroEndpointV2,
    MessagingFee,
    MessagingReceipt,
    Origin
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {ILayerZeroComposer} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroComposer.sol";

import {OAppUpgradeable} from "../OAppUpgradeable.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {OAppPreCrimeSimulatorUpgradeable} from "../../precrime/OAppPreCrimeSimulatorUpgradeable.sol";

library MsgCodec {
    uint8 internal constant VANILLA_TYPE = 1;
    uint8 internal constant COMPOSED_TYPE = 2;
    uint8 internal constant ABA_TYPE = 3;
    uint8 internal constant COMPOSED_ABA_TYPE = 4;

    uint8 internal constant MSG_TYPE_OFFSET = 0;
    uint8 internal constant SRC_EID_OFFSET = 1;
    uint8 internal constant VALUE_OFFSET = 5;

    function encode(uint8 _type, uint32 _srcEid) internal pure returns (bytes memory) {
        return abi.encodePacked(_type, _srcEid);
    }

    function encode(uint8 _type, uint32 _srcEid, uint256 _value) internal pure returns (bytes memory) {
        return abi.encodePacked(_type, _srcEid, _value);
    }

    function msgType(bytes calldata _message) internal pure returns (uint8) {
        return uint8(bytes1(_message[MSG_TYPE_OFFSET:SRC_EID_OFFSET]));
    }

    function srcEid(bytes calldata _message) internal pure returns (uint32) {
        return uint32(bytes4(_message[SRC_EID_OFFSET:VALUE_OFFSET]));
    }

    function value(bytes calldata _message) internal pure returns (uint256) {
        return uint256(bytes32(_message[VALUE_OFFSET:]));
    }
}

contract OmniCounter is ILayerZeroComposer, OAppUpgradeable, OAppPreCrimeSimulatorUpgradeable {
    using MsgCodec for bytes;
    using OptionsBuilder for bytes;

    struct OmniCounterStorage {
        uint256 _count;
        uint256 _composedCount;
        address _admin;
        uint32 _eid;
        mapping(uint32 => mapping(bytes32 => uint64)) _maxReceivedNonce;
        bool _orderedNonce;
        mapping(uint32 => uint256) _inboundCount;
        mapping(uint32 => uint256) _outboundCount;
    }

    // keccak256(abi.encode(uint256(keccak256("layerzero.storage.OmniCounter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OmniCounterStorageLocation =
        0xd4db8088a65cc59d2138ca9f907d6fc329b2709b153e277ef244ab673ab65c00;

    function _getOmniCounterStorage() internal pure returns (OmniCounterStorage storage $) {
        assembly {
            $.slot := OmniCounterStorageLocation
        }
    }

    function initialize(address _endpoint, address _owner) external initializer {
        __OApp_init(_endpoint, _owner);
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        $._admin = msg.sender;
        $._eid = ILayerZeroEndpointV2(_endpoint).eid();
    }

    function count() external view returns (uint256) {
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        return $._count;
    }

    function composedCount() external view returns (uint256) {
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        return $._composedCount;
    }

    function admin() external view returns (address) {
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        return $._admin;
    }

    function eid() external view returns (uint32) {
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        return $._eid;
    }

    function inboundCount(uint32 srcEid) external view returns (uint256) {
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        return $._inboundCount[srcEid];
    }

    function outboundCount(uint32 dstEid) external view returns (uint256) {
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        return $._outboundCount[dstEid];
    }

    modifier onlyAdmin() {
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        require(msg.sender == $._admin, "only admin");
        _;
    }

    // -------------------------------
    // Only Admin
    function setAdmin(address _admin) external onlyAdmin {
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        $._admin = _admin;
    }

    function withdraw(address payable _to, uint256 _amount) external onlyAdmin {
        (bool success,) = _to.call{value: _amount}("");
        require(success, "OmniCounter: withdraw failed");
    }

    // -------------------------------
    // Send
    function increment(uint32 _eid, uint8 _type, bytes calldata _options) external payable {
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        //        bytes memory options = combineOptions(_eid, _type, _options);
        _lzSend(_eid, MsgCodec.encode(_type, $._eid), _options, MessagingFee(msg.value, 0), payable(msg.sender));
        _incrementOutbound(_eid);
    }

    // this is a broken function to skip incrementing outbound count
    // so that preCrime will fail
    function brokenIncrement(uint32 _eid, uint8 _type, bytes calldata _options) external payable onlyAdmin {
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        //        bytes memory options = combineOptions(_eid, _type, _options);
        _lzSend(_eid, MsgCodec.encode(_type, $._eid), _options, MessagingFee(msg.value, 0), payable(msg.sender));
    }

    function batchIncrement(uint32[] calldata _eids, uint8[] calldata _types, bytes[] calldata _options)
        external
        payable
    {
        require(_eids.length == _options.length && _eids.length == _types.length, "OmniCounter: length mismatch");

        OmniCounterStorage storage $ = _getOmniCounterStorage();
        MessagingReceipt memory receipt;
        uint256 providedFee = msg.value;
        for (uint256 i = 0; i < _eids.length; i++) {
            address refundAddress = i == _eids.length - 1 ? msg.sender : address(this);
            uint32 dstEid = _eids[i];
            uint8 msgType = _types[i];
            //            bytes memory options = combineOptions(dstEid, msgType, _options[i]);
            receipt = _lzSend(
                dstEid,
                MsgCodec.encode(msgType, $._eid),
                _options[i],
                MessagingFee(providedFee, 0),
                payable(refundAddress)
            );
            _incrementOutbound(dstEid);
            providedFee -= receipt.fee.nativeFee;
        }
    }

    // -------------------------------
    // View
    function quote(uint32 _eid, uint8 _type, bytes calldata _options)
        public
        view
        returns (uint256 nativeFee, uint256 lzTokenFee)
    {
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        //        bytes memory options = combineOptions(_eid, _type, _options);
        MessagingFee memory fee = _quote(_eid, MsgCodec.encode(_type, $._eid), _options, false);
        return (fee.nativeFee, fee.lzTokenFee);
    }

    // @dev enables preCrime simulator
    // @dev routes the call down from the OAppPreCrimeSimulator, and up to the OApp
    function _lzReceiveSimulate(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal virtual override {
        _lzReceive(_origin, _guid, _message, _executor, _extraData);
    }

    // -------------------------------
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address, /*_executor*/
        bytes calldata /*_extraData*/
    ) internal override {
        _acceptNonce(_origin.srcEid, _origin.sender, _origin.nonce);
        uint8 messageType = _message.msgType();

        OmniCounterStorage storage $ = _getOmniCounterStorage();
        if (messageType == MsgCodec.VANILLA_TYPE) {
            $._count++;

            //////////////////////////////// IMPORTANT //////////////////////////////////
            /// if you request for msg.value in the options, you should also encode it
            /// into your message and check the value received at destination (example below).
            /// if not, the executor could potentially provide less msg.value than you requested
            /// leading to unintended behavior. Another option is to assert the executor to be
            /// one that you trust.
            /////////////////////////////////////////////////////////////////////////////
            require(msg.value >= _message.value(), "OmniCounter: insufficient value");

            _incrementInbound(_origin.srcEid);
        } else if (messageType == MsgCodec.COMPOSED_TYPE || messageType == MsgCodec.COMPOSED_ABA_TYPE) {
            $._count++;
            _incrementInbound(_origin.srcEid);
            endpoint().sendCompose(address(this), _guid, 0, _message);
        } else if (messageType == MsgCodec.ABA_TYPE) {
            $._count++;
            _incrementInbound(_origin.srcEid);

            // send back to the sender
            _incrementOutbound(_origin.srcEid);
            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 10);
            _lzSend(
                _origin.srcEid,
                MsgCodec.encode(MsgCodec.VANILLA_TYPE, $._eid, 10),
                options,
                MessagingFee(msg.value, 0),
                payable(address(this))
            );
        } else {
            revert("invalid message type");
        }
    }

    function _incrementInbound(uint32 _srcEid) internal {
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        $._inboundCount[_srcEid]++;
    }

    function _incrementOutbound(uint32 _dstEid) internal {
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        $._outboundCount[_dstEid]++;
    }

    function lzCompose(address _oApp, bytes32, /*_guid*/ bytes calldata _message, address, bytes calldata)
        external
        payable
        override
    {
        require(_oApp == address(this), "!oApp");
        require(msg.sender == address(endpoint()), "!endpoint");

        uint8 msgType = _message.msgType();
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        if (msgType == MsgCodec.COMPOSED_TYPE) {
            $._composedCount += 1;
        } else if (msgType == MsgCodec.COMPOSED_ABA_TYPE) {
            $._composedCount += 1;

            uint32 srcEid = _message.srcEid();
            _incrementOutbound(srcEid);
            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
            _lzSend(
                srcEid,
                MsgCodec.encode(MsgCodec.VANILLA_TYPE, $._eid),
                options,
                MessagingFee(msg.value, 0),
                payable(address(this))
            );
        } else {
            revert("invalid message type");
        }
    }

    // -------------------------------
    // Ordered OApp
    // this demonstrates how to build an app that requires execution nonce ordering
    // normally an app should decide ordered or not on contract construction
    // this is just a demo
    function setOrderedNonce(bool _orderedNonce) external onlyOwner {
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        $._orderedNonce = _orderedNonce;
    }

    function _acceptNonce(uint32 _srcEid, bytes32 _sender, uint64 _nonce) internal virtual {
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        uint64 currentNonce = $._maxReceivedNonce[_srcEid][_sender];
        if ($._orderedNonce) {
            require(_nonce == currentNonce + 1, "OApp: invalid nonce");
        }
        // update the max nonce anyway. once the ordered mode is turned on, missing early nonces will be rejected
        if (_nonce > currentNonce) {
            $._maxReceivedNonce[_srcEid][_sender] = _nonce;
        }
    }

    function nextNonce(uint32 _srcEid, bytes32 _sender) public view virtual override returns (uint64) {
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        if ($._orderedNonce) {
            return $._maxReceivedNonce[_srcEid][_sender] + 1;
        } else {
            return 0; // path nonce starts from 1. if 0 it means that there is no specific nonce enforcement
        }
    }

    // TODO should override oApp version with added ordered nonce increment
    // a governance function to skip nonce
    function skipInboundNonce(uint32 _srcEid, bytes32 _sender, uint64 _nonce) public virtual onlyOwner {
        endpoint().skip(address(this), _srcEid, _sender, _nonce);
        OmniCounterStorage storage $ = _getOmniCounterStorage();
        if ($._orderedNonce) {
            $._maxReceivedNonce[_srcEid][_sender]++;
        }
    }

    function isPeer(uint32 _eid, bytes32 _peer) public view override returns (bool) {
        return peers(_eid) == _peer;
    }

    // @dev Batch send requires overriding this function from OAppSender because the msg.value contains multiple fees
    function _payNative(uint256 _nativeFee) internal virtual override returns (uint256 nativeFee) {
        if (msg.value < _nativeFee) revert NotEnoughNative(msg.value);
        return _nativeFee;
    }

    // be able to receive ether
    receive() external payable virtual {}

    fallback() external payable {}
}
