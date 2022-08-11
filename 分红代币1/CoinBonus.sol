// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./lib/SafeMathUint.sol";
import "./lib/SafeMathInt.sol";


// Reference: https://github.com/Roger-Wu/erc1726-dividend-paying-token 
contract CoinBonus is  Ownable {
    using SafeMath for uint256;
    using SafeMathUint for uint256;
    using SafeMathInt for int256;
    using SafeERC20 for IERC20;

    bool private _paused;
    mapping(address => bool) public operators;

    IERC20 public rewardToken; // Distribute reward token from transfer tax.


    mapping(address => uint256) private _balances;
    uint256 public totalSupply;
    uint256 public accPerShare;
    uint256 public rewardTotal;

    uint256 constant internal magnitude = 2**128;
    mapping(address => int256) internal magnifiedDividendCorrections;
    mapping(address => uint256) public rewardTaked;

    modifier onlyOperator() {
        require(operators[msg.sender], "Operator: caller is not the operator");
        _;
    }

    event DividendsDistributed(address indexed from,uint256 weiAmount);
    event DividendWithdrawn(address indexed to,uint256 weiAmount);

    constructor()  {
        _paused = false;
        operators[msg.sender] = true;
    }

    function initData(IERC20 _rewardToken) public onlyOwner {
        rewardToken = _rewardToken;
    }
    //----------------------------------------------------------------

    function addReward(uint256 _rewardAmount) public  onlyOperator {
        if (_paused) {
            return;
        }

        if (totalSupply == 0 || _rewardAmount == 0) {
            return;
        }

        rewardTotal = rewardTotal.add(_rewardAmount);
        accPerShare = accPerShare.add(_rewardAmount.mul(magnitude) / totalSupply);
        emit DividendsDistributed(msg.sender, _rewardAmount);

    }

    function takeReward() public {
        address _user = msg.sender;
        uint256 _reward = withdrawableDividendOf(_user);
        if (_reward > 0) {
            rewardTaked[_user] = rewardTaked[_user].add(_reward);
            
            rewardToken.safeTransfer(_user, _reward);
            emit DividendWithdrawn(_user, _reward);
        }
    }

    //----------------------------------------------------------------
    function setBalance(address account, uint256 newBalance) public {
        uint256 currentBalance = balanceOf(account);

        if(newBalance > currentBalance) {
            uint256 mintAmount = newBalance.sub(currentBalance);
            mint(account, mintAmount);
        } else if(newBalance < currentBalance) {
            uint256 burnAmount = currentBalance.sub(newBalance);
            burn(account, burnAmount);
        }
    }

    function mint(address account, uint256 value) internal {
        _mint(account, value);

        magnifiedDividendCorrections[account] = magnifiedDividendCorrections[account]
        .sub( (accPerShare.mul(value)).toInt256Safe() );
    }

    function burn(address account, uint256 value) internal {
        _burn(account, value);

        magnifiedDividendCorrections[account] = magnifiedDividendCorrections[account]
        .add( (accPerShare.mul(value)).toInt256Safe() );
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        totalSupply += amount;
        _balances[account] += amount;
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        totalSupply -= amount;
    }


    //----------------------------------------------------------------
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    //可领取数量
    function dividendOf(address _owner) public view returns(uint256) {
        return withdrawableDividendOf(_owner);
    }

    //可领取数量
    function withdrawableDividendOf(address _owner) public view returns(uint256) {
        return accumulativeDividendOf(_owner).sub(rewardTaked[_owner]);
    }

    //已领取数量
    function taked(address _owner) public view returns(uint256) {
        return rewardTaked[_owner];
    }

    //累计可以领取数量
    function accumulativeDividendOf(address _owner) public view returns(uint256) {
        return accPerShare.mul( balanceOf(_owner) ).toInt256Safe()
        .add(magnifiedDividendCorrections[_owner]).toUint256Safe() / magnitude;
    }

    //----------------------------------------------------------------


}