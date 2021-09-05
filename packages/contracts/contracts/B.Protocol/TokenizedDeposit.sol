// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./BAMM.sol";
import "./../Dependencies/Ownable.sol";
import "./../Dependencies/IERC20.sol";
import "./../Dependencies/SafeMath.sol";

interface CToken {
    function balanceOfUnderlying(address account) external returns (uint);
}


contract Avatar is Ownable {
    using SafeMath for uint256;

    IERC20 public immutable LUSD;
    IERC20 public immutable LQTY;
    BAMM public immutable bamm;

    constructor(IERC20 _LUSD, IERC20 _LQTY, BAMM _bamm) public {
        LUSD = _LUSD;
        LQTY = _LQTY;
        bamm = _bamm;

        _LUSD.approve(address(_bamm), uint(-1));
    }

    function mint(uint lusdAmount) external onlyOwner returns(uint) {
        // lusd balance is assumed to be already here
        uint balanceBefore = bamm.balanceOf(address(this));
        bamm.deposit(lusdAmount);
        uint balanceAfter = bamm.balanceOf(address(this));
        uint balanceDiff = balanceAfter.sub(balanceBefore);

        return balanceDiff;
    }

    function burn(uint shareAmount, address payable dest) external onlyOwner returns(uint) {
        uint lusdBalanceBefore = LUSD.balanceOf(address(this));
        uint ethBalanceBefore = address(this).balance;

        bamm.withdraw(shareAmount);

        uint lusdBalanceAfter = LUSD.balanceOf(address(this));
        uint ethBalanceAfter = address(this).balance;

        LUSD.transfer(dest, lusdBalanceAfter.sub(lusdBalanceBefore));
        dest.transfer(ethBalanceAfter.sub(ethBalanceBefore));
    }

    function harvestLqty(address dest) external onlyOwner returns(uint) {
        bamm.withdraw(0);
        LQTY.transfer(dest, LQTY.balanceOf(address(this)));
    }

    receive() external payable {}
}

contract BSPToken {
    using SafeMath for uint256;

    IERC20 public immutable LUSD;
    IERC20 public immutable LQTY;
    BAMM public immutable bamm;
    CToken public immutable ctoken;

    uint public totalSupply;
    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;
    string public constant name = "B.Protocol's Wrapped Stability Pool Token";
    string public constant symbol = "BSPT";
    uint8 public constant decimals = 18;  // 18 is the most common number of decimal places

    mapping(address => uint) public expectedCTokenBalance;
    mapping(address => Avatar) public avatars;

    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);    

    constructor(IERC20 _LUSD, IERC20 _LQTY, BAMM _bamm, CToken _ctoken) public {
        LUSD = _LUSD;
        LQTY = _LQTY;
        bamm = _bamm;
        ctoken = _ctoken;
    }

    function getAvatar(address a) internal returns(Avatar) {
        if(avatars[a] == Avatar(0)) {
            Avatar av = new Avatar(LUSD, LQTY, bamm);
            avatars[a] = av;
            LUSD.approve(address(av), uint(-1));

            return av;
        }

        return avatars[a];
    }

    function mint(uint lusdAmount) external returns(uint) {
        Avatar a = getAvatar(msg.sender);
        LUSD.transferFrom(msg.sender, address(a), lusdAmount);
        uint deltaBalance = a.mint(lusdAmount);
        balanceOf[msg.sender] = balanceOf[msg.sender].add(deltaBalance);

        emit Transfer(address(0), msg.sender, deltaBalance);

        totalSupply = totalSupply.add(deltaBalance);

        return deltaBalance;
    }

    function burn(uint tokenAmount) external returns(uint) {
        Avatar a = getAvatar(msg.sender);

        uint currBal = balanceOf[msg.sender];
        require(tokenAmount <= currBal, "burn: low-balance");

        balanceOf[msg.sender] = currBal.sub(tokenAmount);
        a.burn(tokenAmount, msg.sender);

        totalSupply = totalSupply.sub(tokenAmount);

        emit Transfer(msg.sender, address(0), tokenAmount); 
    }

    function harvestLqty() external {
        getAvatar(msg.sender).harvestLqty(msg.sender);
    }

    function liquidate(address user, uint tokenAmount) external {
        require(expectedCTokenBalance[user].sub(tokenAmount) >= ctoken.balanceOfUnderlying(user), "liquidate: not-allowed");

        expectedCTokenBalance[user] = expectedCTokenBalance[user].sub(tokenAmount);
        balanceOf[msg.sender] = balanceOf[msg.sender].sub(tokenAmount);

        getAvatar(user).burn(tokenAmount, msg.sender);

        emit Transfer(msg.sender, address(0), tokenAmount);        
    }

    function _transfer(address src, address dest, uint amount) internal returns(bool) {
        uint currBal = balanceOf[src];
        require(amount <= currBal, "_transfer: low-balance");
        require(src == address(ctoken) || dest == address(ctoken), "_transfer: src and dest not ctoken");
        require(src != dest, "_transfer: dest == src");

        if(dest == address(ctoken)) {
            expectedCTokenBalance[src] = expectedCTokenBalance[src].add(amount);
        }
        else if(src == address(ctoken)) {
            uint currCBal = expectedCTokenBalance[dest];
            if(currCBal < amount) expectedCTokenBalance[dest] = 0;
            else expectedCTokenBalance[dest] = currCBal.sub(amount);
        }
        else revert("_transfer: unsupported src and dest");

        balanceOf[src] = currBal.sub(amount);
        balanceOf[dest] = balanceOf[dest].add(amount);

        emit Transfer(src, dest, amount);

        return true;
    }

    function transfer(address dest, uint amount) external returns(bool) {
        return _transfer(msg.sender, dest, amount);
    }

    function tranferFrom(address sender, address recipient, uint amount) external returns(bool) {
        require(allowance[sender][recipient] >= amount, "tranferFrom: insufficient allowance");
        allowance[sender][recipient] = allowance[sender][recipient].sub(amount);

        require(_transfer(sender, recipient, amount), "tranferFrom: _transfer failed");

        return true;
    }

    function approve(address spender, uint tokens) external returns (bool) {
        allowance[msg.sender][spender] = tokens;
        emit Approval(msg.sender, spender, tokens);
        return true;
    }
}