// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {OFTAdapterUpgradeable} from "../../contracts/oft/OFTAdapterUpgradeable.sol";

contract OFTAdapterMock is OFTAdapterUpgradeable {
    // @dev expose internal functions for testing purposes
    function debit(uint256 _amountToSendLD, uint256 _minAmountToCreditLD, uint32 _dstEid)
        public
        returns (uint256 amountDebitedLD, uint256 amountToCreditLD)
    {
        return _debit(_amountToSendLD, _minAmountToCreditLD, _dstEid);
    }

    function debitView(uint256 _amountToSendLD, uint256 _minAmountToCreditLD, uint32 _dstEid)
        public
        view
        returns (uint256 amountDebitedLD, uint256 amountToCreditLD)
    {
        return _debitView(_amountToSendLD, _minAmountToCreditLD, _dstEid);
    }

    function credit(address _to, uint256 _amountToCreditLD, uint32 _srcEid) public returns (uint256 amountReceivedLD) {
        return _credit(_to, _amountToCreditLD, _srcEid);
    }

    function increaseOutboundAmount(uint256 _amount) public {
        _increaseOutboundAmount(_amount);
    }

    function removeDust(uint256 _amountLD) public view returns (uint256 amountLD) {
        return _removeDust(_amountLD);
    }
}
