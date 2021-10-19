// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./../Dependencies/Ownable.sol";
import "./../Dependencies/IERC20.sol";
import "./../Dependencies/SafeMath.sol";


interface CrvGauge {
    function deposit(uint _value, address _addr, bool _claimRewards) external;
    function withdraw(uint _value, bool _claimRewards) external;
    function claim_rewards(address _addr, address _receiver) external;    
}

interface Cauldron {
    function addCollateral(address to, bool skim, uint share) external;
    function removeCollateral(address to, uint share) external;

    function borrow(address to, uint amount) external returns (uint part, uint share);
    function repay(address to, bool skim, uint part) external;

    // view functions

    // this returns the precise collateral
    function userCollateralShare(address user) external returns(uint);

    // this does not returnt the actual borrow part, but we only need it to test if 0
    function userBorrowPart(address user) external returns(uint);
}

interface BAMM {
    function deposit(uint mimAmount) external;
    function withdraw(uint shareAmount) external;
}

// TODO - make a proxy for cheap deployment
contract Avatar is Ownable {
    using SafeMath for uint256;

    IERC20 public immutable mim;
    IERC20 public immutable mim3Pool;
    IERC20 public immutable bmim3Pool;
    CrvGauge public immutable gauge;
    Cauldron public immutable cauldron;
    BAMM public immutable bamm;
    address public user;

    modifier onlyUser() {
        require(msg.sender == user, "caller is not the user");
        _;
    }    

    constructor(IERC20 _mim, IERC20 _bmim3Pool, IERC20 _mim3Pool, CrvGauge _gauge, Cauldron _cauldron, BAMM _bamm, address _user) public {
        mim3Pool = _mim3Pool;
        bmim3Pool = _bmim3Pool;
        mim = _mim;
        gauge = _gauge;
        cauldron = _cauldron;
        bamm = _bamm;
        user = _user;

        // give allowance to the curvfi guague
        _mim3Pool.approve(address(_gauge), uint(-1));
        _bmim3Pool.approve(address(_cauldron), uint(-1));
        _mim.approve(address(_bamm), uint(-1));
        _mim.approve(address(_cauldron), uint(-1));        
    }

    //////////////////////////////////////////////////////////////////

    function mint(uint m3pAmount) external onlyOwner {
        gauge.deposit(m3pAmount, address(this), false);
    }

    function burn(uint m3pAmount, address dest) external onlyOwner {
        gauge.withdraw(m3pAmount, true);
        mim3Pool.transfer(dest, m3pAmount);
    }

    function harvest(address dest) external onlyOwner {
        gauge.claim_rewards(address(this), dest);
    }

    //////////////////////////////////////////////////////////////////

    function addCollateral(uint bmim3PoolAmount) external onlyOwner {
        cauldron.addCollateral(address(this), false, bmim3PoolAmount);
    }

    function removeCollateral(uint bmim3PoolAmount) external onlyOwner {
        cauldron.removeCollateral(address(this), bmim3PoolAmount);
    }

    function borrow(uint mimAmount) external onlyUser {
        cauldron.borrow(address(this), mimAmount);
    }

    function repay(uint part) external onlyUser {
        cauldron.repay(address(this), false, part);
    }

    //////////////////////////////////////////////////////////////////

    function fetchEth(address payable dest, uint amount) external onlyUser {
        dest.transfer(amount);
    }

    function fetchToken(IERC20 token, address dest, uint amount) external onlyUser {
        // avoid 0 test to prevent rounding errors.
        if(token == mim) require(cauldron.userBorrowPart(address(this)) < 1e16, "fetchToken/repay-debt-first");

        token.transfer(dest, amount);
    }

    //////////////////////////////////////////////////////////////////

    function bammDeposit(uint mimAmount) external onlyUser {
        bamm.deposit(mimAmount);
    }

    function bammWithdraw(uint shareAmount) external onlyUser {
        bamm.withdraw(shareAmount);
    }    

    receive() external payable {}
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

contract BMCrvToken is Ownable {
    using SafeMath for uint256;

    IERC20 public immutable mim;
    IERC20 public immutable mim3Pool;
    CrvGauge public immutable gauge;
    Cauldron public cauldron;
    BAMM public immutable bamm;

    uint public totalSupply;
    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;
    string public constant name = "B.Protocol's Wrapped MIM-3-POOL-f Token";
    string public constant symbol = "BM3P";
    uint8 public constant decimals = 18;  // 18 is the most common number of decimal places

    mapping(address => uint) public expectedCauldronBalance;
    mapping(address => Avatar) public avatars;

    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);    

    constructor(IERC20 _mim, IERC20 _mim3Pool, CrvGauge _gauge, BAMM _bamm) public {
        mim3Pool = _mim3Pool;
        mim = _mim;
        gauge = _gauge;
        bamm = _bamm;
    }

    function setCauldron(Cauldron _cauldron) external onlyOwner {
        require(cauldron == Cauldron(address(0x0)), "setCauldron: already-init");
        cauldron = _cauldron;
    }

    function getAvatar(address a) public returns(Avatar) {
        if(avatars[a] == Avatar(0)) {
            Avatar av = new Avatar(mim, IERC20(address(this)), mim3Pool, gauge, cauldron, bamm, a);
            avatars[a] = av;

            return av;
        }

        return avatars[a];
    }

    function mint(uint mim3PoolAmount) external returns(uint) {
        Avatar a = getAvatar(msg.sender);
        mim3Pool.transferFrom(msg.sender, address(a), mim3PoolAmount);
        a.mint(mim3PoolAmount);
        balanceOf[address(a)] = balanceOf[address(a)].add(mim3PoolAmount);

        emit Transfer(address(0), address(a), mim3PoolAmount);

        totalSupply = totalSupply.add(mim3PoolAmount);

        a.addCollateral(mim3PoolAmount);

        return mim3PoolAmount;
    }

    function burn(uint mim3PoolAmount) external returns(uint) {
        Avatar a = getAvatar(msg.sender);

        try a.removeCollateral(mim3PoolAmount) {}
        catch (bytes memory /* reason */) {/* life's a beach */}

        uint currBal = balanceOf[address(a)];
        require(mim3PoolAmount <= currBal, "burn: low-balance");

        balanceOf[address(a)] = currBal.sub(mim3PoolAmount);
        a.burn(mim3PoolAmount, msg.sender);

        totalSupply = totalSupply.sub(mim3PoolAmount);

        emit Transfer(address(a), address(0), mim3PoolAmount); 
    }

    function harvest() external {
        getAvatar(msg.sender).harvest(msg.sender);
    }

    function liquidate(address payable user, uint tokenAmount) external {
        require(expectedCauldronBalance[user].sub(tokenAmount) >= cauldron.userCollateralShare(user), "liquidate: not-allowed");

        expectedCauldronBalance[user] = expectedCauldronBalance[user].sub(tokenAmount);
        balanceOf[msg.sender] = balanceOf[msg.sender].sub(tokenAmount);

        Avatar(user).burn(tokenAmount, msg.sender);

        emit Transfer(msg.sender, address(0), tokenAmount);        
    }

    function _transfer(address src, address dest, uint amount) internal returns(bool) {
        uint currBal = balanceOf[src];
        require(amount <= currBal, "_transfer: low-balance");
        require(src == address(cauldron) || dest == address(cauldron), "_transfer: src and dest not ctoken");
        require(src != dest, "_transfer: dest == src");
        // TODO - very that if src is not cauldron, then it is a registered avatar? or maybe let only avatars and cauldorn to send tokens

        if(dest == address(cauldron)) {
            expectedCauldronBalance[src] = expectedCauldronBalance[src].add(amount);
        }
        else if(src == address(cauldron)) {
            uint currCBal = expectedCauldronBalance[dest];
            if(currCBal < amount) expectedCauldronBalance[dest] = 0;
            else expectedCauldronBalance[dest] = currCBal.sub(amount);
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

    function transferFrom(address sender, address recipient, uint amount) external returns(bool) {
        require(allowance[sender][recipient] >= amount, "transferFrom: insufficient allowance");
        
        if(allowance[sender][recipient] != uint(-1)) {
            allowance[sender][recipient] = allowance[sender][recipient].sub(amount);
        }

        require(_transfer(sender, recipient, amount), "transferFrom: _transfer failed");

        return true;
    }

    function approve(address spender, uint tokens) external returns (bool) {
        allowance[msg.sender][spender] = tokens;
        emit Approval(msg.sender, spender, tokens);
        return true;
    }
}