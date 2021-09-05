// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./../Dependencies/IERC20.sol";

contract MockCToken {
    mapping(address => uint) public balanceOfUnderlying;
    
    function setUnderlyingBalance(address user, uint bal) external {
        balanceOfUnderlying[user] = bal;
    }

    function transfer(IERC20 token, address dest, uint amount) external {
        token.transfer(dest, amount);
    }
}