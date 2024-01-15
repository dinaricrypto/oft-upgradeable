// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IOAppCore, ILayerZeroEndpointV2} from "LayerZero-v2/oapp/contracts/oapp/interfaces/IOAppCore.sol";

/**
 * @title OAppCore
 * @dev Abstract contract implementing the IOAppCore interface with basic OApp configurations.
 */
abstract contract OAppCoreUpgradeable is IOAppCore, Initializable, OwnableUpgradeable {
    struct OAppCoreStorage {
        // The address of the LayerZero endpoint associated with the given OApp
        ILayerZeroEndpointV2 _endpoint;
        // Mapping to store peers associated with corresponding endpoints
        mapping(uint32 => bytes32) _peers;
    }

    // keccak256(abi.encode(uint256(keccak256("layerzero.storage.OAppCore")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OAppCoreStorageLocation =
        0x58caa5f4171d954fbd20b1d134833615ec3c90ab38e1c4443a45151b8ad01600;

    function _getOAppCoreStorage() private pure returns (OAppCoreStorage storage $) {
        assembly {
            $.slot := OAppCoreStorageLocation
        }
    }

    /**
     * @dev Initialize the OAppCore with the provided endpoint and owner.
     * @param _endpoint The address of the LOCAL Layer Zero endpoint.
     * @param _owner The address of the owner of the OAppCore.
     */
    function __OAppCore_init(address _endpoint, address _owner) internal onlyInitializing {
        __Ownable_init(_owner);
        __OAppCore_init_unchained(_endpoint, _owner);
    }

    function __OAppCore_init_unchained(address _endpoint, address _owner) internal onlyInitializing {
        OAppCoreStorage storage $ = _getOAppCoreStorage();
        $._endpoint = ILayerZeroEndpointV2(_endpoint);
        $._endpoint.setDelegate(_owner); // @dev By default, the owner is the delegate
    }

    // The LayerZero endpoint associated with the given OApp
    function endpoint() public view virtual returns (ILayerZeroEndpointV2) {
        OAppCoreStorage storage $ = _getOAppCoreStorage();
        return $._endpoint;
    }

    // Mapping to store peers associated with corresponding endpoints
    function peers(uint32 eid) public view virtual returns (bytes32 peer) {
        OAppCoreStorage storage $ = _getOAppCoreStorage();
        return $._peers[eid];
    }

    /**
     * @notice Sets the peer address (OApp instance) for a corresponding endpoint.
     * @param _eid The endpoint ID.
     * @param _peer The address of the peer to be associated with the corresponding endpoint.
     *
     * @dev Only the owner/admin of the OApp can call this function.
     * @dev Indicates that the peer is trusted to send LayerZero messages to this OApp.
     * @dev Set this to bytes32(0) to remove the peer address.
     * @dev Peer is a bytes32 to accommodate non-evm chains.
     */
    function setPeer(uint32 _eid, bytes32 _peer) public virtual onlyOwner {
        OAppCoreStorage storage $ = _getOAppCoreStorage();
        $._peers[_eid] = _peer;
        emit PeerSet(_eid, _peer);
    }

    /**
     * @notice Internal function to get the peer address associated with a specific endpoint; reverts if NOT set.
     * ie. the peer is set to bytes32(0).
     * @param _eid The endpoint ID.
     * @return peer The address of the peer associated with the specified endpoint.
     */
    function _getPeerOrRevert(uint32 _eid) internal view virtual returns (bytes32) {
        OAppCoreStorage storage $ = _getOAppCoreStorage();
        bytes32 peer = $._peers[_eid];
        if (peer == bytes32(0)) revert NoPeer(_eid);
        return peer;
    }

    /**
     * @notice Sets the delegate address for the OApp.
     * @param _delegate The address of the delegate to be set.
     *
     * @dev Only the owner/admin of the OApp can call this function.
     * @dev Provides the ability for a delegate to set configs, on behalf of the OApp, directly on the Endpoint contract.
     * @dev Defaults to the owner of the OApp.
     */
    function setDelegate(address _delegate) public onlyOwner {
        OAppCoreStorage storage $ = _getOAppCoreStorage();
        $._endpoint.setDelegate(_delegate);
    }
}
