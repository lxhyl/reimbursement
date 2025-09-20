import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {Expense, ExpenseLib} from "../src/types/Expense.sol";

contract ExpenseTest is Test {
    function test_pack_unpack() public {
        address addr = address(0x1234567890123456789012345678901234567890);
        bool paid = false;
        uint256 amount = 9584 * 1e6;

        Expense expense = ExpenseLib.pack(address(0x1234567890123456789012345678901234567890), false, 9584 * 1e6);

        (address _addr, bool _paid, uint256 _amount) = ExpenseLib.unpack(expense);

        assertEq(addr, _addr);
        assertEq(paid, _paid);
        assertEq(amount, _amount);
    }
}
