// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

import {Week,WeekLib} from "./types/WeekDate.sol";
import {Expense,ExpenseLib} from "./types/Expense.sol";
contract Reimbursement is UUPSUpgradeable, OwnableUpgradeable {
    
    address public relayer;
    modifier onlyRelayer() {
        require(msg.sender == relayer, "Not relayer");
        _;
    }
    event RelayerChange(address oldRelayer, address newRelayer);

    IERC20 immutable public usdc;

    mapping(Week => Expense[]) public expensesOfWeek;
    event ExpenseAdded(Week week, Expense expense);
    error ExpenseAlreadyPaid(Week week, Expense expense);
    event ExpensePaid(Week week, Expense expense);
    
    constructor(address _usdc) {
        usdc = IERC20(_usdc);
    }

    function initialize(address _owner, address _relayer) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(_owner);
        relayer = _relayer;
    }

    struct ReimburseParams {
        address recipient;
        uint256 amount;
        uint256 timestamp;
    }
    function reimburse(ReimburseParams[] calldata _params) onlyRelayer external {
      for (uint256 i = 0; i < _params.length; i++) {
        Week week = WeekLib.getWeek(_params[i].timestamp);
        Expense expense = ExpenseLib.pack(_params[i].recipient, false, _params[i].amount);
        expensesOfWeek[week].push(expense); 
        emit ExpenseAdded(week,expense);
      }
    }
    function distribute(Week[] calldata _weeks, uint256 _totalAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        _checkFund(_totalAmount, deadline, v, r, s);

        for (uint256 i = 0; i < _weeks.length; i++) {
            Week week = _weeks[i];
            Expense[] storage expenses = expensesOfWeek[week];
            for (uint256 j = 0; j < expenses.length; j++) {
                (address recipient, bool paid, uint256 amount) = ExpenseLib.unpack(expenses[j]);
                if(paid) continue;
                Expense paidExpense = ExpenseLib.pack(recipient, true, amount);
                expenses[j] = paidExpense;
                usdc.transfer(recipient, amount);
                emit ExpensePaid(week, paidExpense);
            }
        }
    }
    function claim(Week[] calldata _weeks) external {
        for (uint256 i = 0; i < _weeks.length; i++) {
            Week week = _weeks[i];
            Expense[] storage expenses = expensesOfWeek[week];
            for (uint256 j = 0; j < expenses.length; j++) {
                (address recipient, bool paid, uint256 amount) = ExpenseLib.unpack(expenses[j]);
                if(recipient != msg.sender) continue;
                if(paid) continue;
                Expense paidExpense = ExpenseLib.pack(recipient, true, amount);
                expenses[j] = paidExpense;
                usdc.transfer(recipient, amount);
                emit ExpensePaid(week, paidExpense);
            }
        }
    }
    function _checkFund(uint256 _totalAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) internal {
        // contract balance is enough
        if(usdc.balanceOf(address(this)) >= _totalAmount) return;

        uint256 allowance = usdc.allowance(msg.sender, address(this));
        if(allowance < _totalAmount){
            IERC20Permit(address(usdc)).permit(msg.sender, address(this), _totalAmount, deadline, v, r, s);
        }

        usdc.transferFrom(msg.sender, address(this), _totalAmount);
    }

    // view methods
    function getExpenses(Week[] calldata _weeks) external view returns (Expense[][] memory) {
        Expense[][] memory _expenses = new Expense[][](_weeks.length);
        for (uint256 i = 0; i < _weeks.length; i++) {
            _expenses[i] = expensesOfWeek[_weeks[i]];
        }
        return _expenses;
    }
    //  owner methods
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setRelayer(address _relayer) external onlyOwner {
        emit RelayerChange(relayer,_relayer);
        relayer = _relayer;
    }
    function withdraw(address token, address to, uint256 _amount) external onlyOwner {
        IERC20(token).transfer(to, _amount);
    }
}
