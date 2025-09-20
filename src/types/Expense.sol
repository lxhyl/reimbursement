pragma solidity ^0.8.13;

type Expense is uint256;
using ExpenseLib for Expense;

library ExpenseLib {
   
  function pack(address addr, bool paid, uint256 amount) public pure returns (Expense) {
    require(amount < (1 << 95), "amount overflow");
    uint256 packed = 0;
    packed |= uint256(uint160(addr)) << 96;
    packed |= (paid ? 1 : 0) << 95;
    packed |= amount;
    return Expense.wrap(packed);
  }
  function unpack(Expense expense) public pure returns (address, bool, uint256) {
    uint256 packed = Expense.unwrap(expense);
    address addr = address(uint160(packed >> 96));
    bool paid = (packed >> 95) & 1 == 1;
    uint256 amount = packed & ((1 << 95) - 1);
    return (addr, paid, amount);
  }
}