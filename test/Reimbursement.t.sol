pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Reimbursement} from "../src/Reimbursement.sol";
import {Week, WeekLib} from "../src/types/WeekDate.sol";
import {Expense, ExpenseLib} from "../src/types/Expense.sol";
import {SigUtils} from "./lib/signUtils.sol";

contract MockERC20 is ERC20Permit {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}

contract ReimbursementTest is Test {
    Reimbursement reimbursement;
    MockERC20 usdc;
    SigUtils sigUtils;
    uint256 ownerPrivateKey = 0x1234;
    address owner = vm.addr(ownerPrivateKey);
    uint256 reviewerPrivateKey = 0x1235;
    address reviewer = vm.addr(reviewerPrivateKey);

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC");
        sigUtils = new SigUtils(usdc.DOMAIN_SEPARATOR());

        address implamentation = address(new Reimbursement(address(usdc)));
        reimbursement = Reimbursement(
            address(
                new ERC1967Proxy(
                    implamentation, abi.encodeWithSelector(Reimbursement.initialize.selector, owner, reviewer)
                )
            )
        );

        usdc.mint(owner, 1000000000000000000);
        usdc.mint(reviewer, 1000000000000000000);
        usdc.mint(alice, 100);
        usdc.mint(bob, 50);
    }

    function test_upgrade() public {
        address implamentationBefore = address(reimbursement);
        address implamentation = address(new Reimbursement(address(usdc)));
        vm.prank(owner);
        UUPSUpgradeable(reimbursement).upgradeToAndCall(implamentation, "");
        assertNotEq(address(reimbursement), implamentation);
    }

    function test_reimburse() public {
        skip(13 days);
        Week week = WeekLib.getWeek(block.timestamp);

        vm.startPrank(reviewer);
        Reimbursement.ReimburseParams[] memory params = new Reimbursement.ReimburseParams[](2);
        params[0] = Reimbursement.ReimburseParams({recipient: alice, amount: 10, timestamp: block.timestamp});
        params[1] = Reimbursement.ReimburseParams({recipient: bob, amount: 20, timestamp: block.timestamp});
        reimbursement.reimburse(params);
        vm.stopPrank();

        Week[] memory _weeks = new Week[](1);
        _weeks[0] = week;

        Expense[] memory expenses = (reimbursement.getExpenses(_weeks))[0];
        assertEq(Expense.unwrap(expenses[0]), Expense.unwrap(ExpenseLib.pack(alice, false, 10)));
        assertEq(Expense.unwrap(expenses[1]), Expense.unwrap(ExpenseLib.pack(bob, false, 20)));
    }

    function sign_permit(uint256 privateKey, address owner, address spender, uint256 value, uint256 deadline)
        public
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        SigUtils.Permit memory permit =
            SigUtils.Permit({owner: owner, spender: spender, value: value, nonce: 0, deadline: deadline});
        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (v, r, s) = vm.sign(privateKey, digest);
        return (v, r, s);
    }

    function test_distribute() public {
        Week week = WeekLib.getWeek(block.timestamp);
        vm.startPrank(reviewer);
        Reimbursement.ReimburseParams[] memory params = new Reimbursement.ReimburseParams[](2);
        params[0] = Reimbursement.ReimburseParams({recipient: alice, amount: 10, timestamp: block.timestamp});
        params[1] = Reimbursement.ReimburseParams({recipient: bob, amount: 20, timestamp: block.timestamp});
        reimbursement.reimburse(params);
        vm.stopPrank();

        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = sign_permit(ownerPrivateKey, owner, address(reimbursement), 30, block.timestamp);

        Week[] memory _weeks = new Week[](1);
        _weeks[0] = week;

        uint256 ownerBalanceBefore = usdc.balanceOf(owner);
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        uint256 bobBalanceBefore = usdc.balanceOf(bob);

        vm.startPrank(owner);
        Reimbursement.DistributeParams memory distributeParams = Reimbursement.DistributeParams({
            weekList: _weeks,
            totalAmount: 30,
            deadline: block.timestamp,
            v: v,
            r: r,
            s: s
        });
        reimbursement.distribute(distributeParams);
        vm.stopPrank();

        assertEq(usdc.balanceOf(owner), ownerBalanceBefore - 30);
        assertEq(usdc.balanceOf(alice), aliceBalanceBefore + 10);
        assertEq(usdc.balanceOf(bob), bobBalanceBefore + 20);
    }

    function test_claim() public {
        Week week = WeekLib.getWeek(block.timestamp);
        Week[] memory _weeks = new Week[](1);
        _weeks[0] = week;

        vm.startPrank(reviewer);
        Reimbursement.ReimburseParams[] memory params = new Reimbursement.ReimburseParams[](2);
        params[0] = Reimbursement.ReimburseParams({recipient: alice, amount: 10, timestamp: block.timestamp});
        params[1] = Reimbursement.ReimburseParams({recipient: bob, amount: 20, timestamp: block.timestamp});
        reimbursement.reimburse(params);
        vm.stopPrank();

        uint256 reimbursementBalanceBefore = usdc.balanceOf(address(reimbursement));
        vm.startPrank(owner);
        usdc.transfer(address(reimbursement), 30);
        uint256 reimbursementBalanceAfter = usdc.balanceOf(address(reimbursement));
        assertEq(reimbursementBalanceAfter, reimbursementBalanceBefore + 30);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        reimbursement.claim(_weeks);
        uint256 aliceBalanceAfter = usdc.balanceOf(alice);
        assertEq(aliceBalanceAfter, aliceBalanceBefore + 10);
        vm.stopPrank();

        uint256 bobBalanceBefore = usdc.balanceOf(bob);
        vm.startPrank(bob);
        reimbursement.claim(_weeks);
        vm.stopPrank();
        assertEq(usdc.balanceOf(bob), bobBalanceBefore + 20);

        assertEq(usdc.balanceOf(address(reimbursement)), 0);
    }

    function test_reimburseWithDistribute() public {
        Week week = WeekLib.getWeek(block.timestamp);
        Week[] memory _weeks = new Week[](1);
        _weeks[0] = week;

        Reimbursement.ReimburseParams[] memory reimburseParams = new Reimbursement.ReimburseParams[](2);
        reimburseParams[0] = Reimbursement.ReimburseParams({recipient: alice, amount: 10, timestamp: block.timestamp});
        reimburseParams[1] = Reimbursement.ReimburseParams({recipient: bob, amount: 20, timestamp: block.timestamp});

        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = sign_permit(reviewerPrivateKey, reviewer, address(reimbursement), 30, block.timestamp);

        Reimbursement.DistributeParams memory distributeParams = Reimbursement.DistributeParams({
            weekList: _weeks,
            totalAmount: 30,
            deadline: block.timestamp,
            v: v,
            r: r,
            s: s
        });

        uint256 reviewerBalanceBefore = usdc.balanceOf(reviewer);
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        uint256 bobBalanceBefore = usdc.balanceOf(bob);

        vm.startPrank(reviewer);
        reimbursement.reimburseWithDistribute(reimburseParams, distributeParams);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(reimbursement)), 0);
        assertEq(usdc.balanceOf(reviewer), reviewerBalanceBefore - 30);
        assertEq(usdc.balanceOf(alice), aliceBalanceBefore + 10);
        assertEq(usdc.balanceOf(bob), bobBalanceBefore + 20);
    }
}
