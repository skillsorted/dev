// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;
import "./../../Dependencies/IERC20.sol";


contract CrvGauge {
    IERC20 gem;
    IERC20 crop1;
    IERC20 crop2;

    mapping(address => uint) public balanceOf;

    constructor(IERC20 _gem, IERC20 _crop1, IERC20 _crop2) public {
        gem = _gem;
        crop1 = _crop1;
        crop2 = _crop2;
    }

    function claim_rewards(address _addr, address _receiver) public {
        crop1.transfer(_receiver, 1e18);
        crop2.transfer(_receiver, 2e18);        
    }

    function deposit(uint value, address _addr, bool _claimRewards) public {
        gem.transferFrom(msg.sender, address(this), value);
        balanceOf[_addr] += value;

        if(_claimRewards) claim_rewards(msg.sender, msg.sender);
    }

    function withdraw(uint value, bool _claimRewards) public {
        gem.transfer(msg.sender, value);

        require(balanceOf[msg.sender] >= value, "CrvGauge/withdraw-insufficient-balance");
        balanceOf[msg.sender] -= value;

        if(_claimRewards) claim_rewards(msg.sender, msg.sender);
    }
}

contract Cauldron {
    mapping(address => uint) public userCollateralShare;
    mapping(address => uint) public userBorrowPart;

    IERC20 collateral;
    IERC20 debt;

    constructor(IERC20 _collateral, IERC20 _debt) public {
        collateral = _collateral;
        debt = _debt;
    }

    function addCollateral(address to, bool skim, uint share) external {
        collateral.transferFrom(msg.sender, address(this), share);
        userCollateralShare[to] += share;

        require(! skim, "skim is not supported");
    }

    function removeCollateral(address to, uint share) external {
        require(userCollateralShare[msg.sender] >= share, "removeCollateral: broke");
        userCollateralShare[msg.sender] -= share;

        collateral.transfer(to, share);
    }

    function borrow(address to, uint amount) external returns(uint part, uint share) {
        debt.transfer(to, amount);
        userBorrowPart[msg.sender] += amount;

        return (amount, amount);
    }

    function repay(address to, bool skim, uint part) external {
        require(userBorrowPart[to] >= part, "repay: small debt");
        require(! skim, "repay: skim unsupported");

        userBorrowPart[to] -= part;
        debt.transferFrom(msg.sender, address(this), part);
    }

    function liquidate(address user, uint amount) external {
        require(userCollateralShare[user] >= amount, "liquiate: collateral-not-enough");
        userCollateralShare[user] -= amount;

        collateral.transfer(msg.sender, amount);
    }
}

contract BAMM {
    IERC20 mim;
    mapping(address=>uint) public balanceOf;

    constructor(IERC20 _mim) public {
        mim = _mim;
    }

    function deposit(uint mimAmount) external {
        mim.transferFrom(msg.sender, address(this), mimAmount);
        balanceOf[msg.sender] += 2 * mimAmount;
    }

    function withdraw(uint share) external {
        require(balanceOf[msg.sender] >= share, "withdraw: insufficient share");
        balanceOf[msg.sender] -= share;

        mim.transfer(msg.sender, share / 2);
    }
}