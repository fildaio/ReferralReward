// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "./Interfaces.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface MaximillionInterface {
    function repayBehalf(address borrower) external payable;
}

interface BankInterface {
    function mint() external payable;

    function mint(uint256 mintAmount) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function repayBorrow(uint256 repayAmount) external payable;

    function balanceOf(address owner) external view returns (uint256);

    function exchangeRateCurrent() external returns (uint256);
}

// 用户的代理人。
// 每个用户有一个代理人，由该代理人代理用户的真实地址与Filda的合约业务进行交互。
contract Agent is AccessControl {
    using SafeMath for uint256;

    bytes32 public constant CLIENT = keccak256("CLIENT");
    bytes32 public constant CALLER = keccak256("CALLER");

    constructor(address clientAddress) {
        _setupRole(CLIENT, clientAddress);
        _setupRole(CALLER, msg.sender);
    }

    receive() external payable {}

    function approve(
        address token,
        address spender,
        uint256 amount
    ) public {
        _byClient();
        IERC20(token).approve(spender, amount);
    }

    function deposit(address fToken, uint256 amount)
        external
        payable
        returns (uint256 fTokenAmount)
    {
        _byClient();

        uint256 balanceBefore = IERC20(fToken).balanceOf(address(this));

        if (msg.value > 0) {
            BankInterface(fToken).mint{value: msg.value}();
        } else {
            BankInterface(fToken).mint(amount);
        }

        uint256 balanceAfter = IERC20(fToken).balanceOf(address(this));
        fTokenAmount = balanceAfter.sub(balanceBefore);
    }

    function borrow(
        address fToken,
        address underlying,
        uint256 amount,
        address caller
    ) external {
        _byClient();

        BankInterface(fToken).borrow(amount);

        if (fToken == underlying) {
            payable(caller).transfer(amount);
        } else {
            IERC20(IFildaToken(fToken).underlying()).transfer(caller, amount);
        }
    }

    function repay(
        address fToken,
        address maximillion,
        uint256 amount
    ) external payable {
        _byClient();

        if (msg.value > 0 && maximillion != address(0)) {
            MaximillionInterface(maximillion).repayBehalf{value: msg.value}(
                address(this)
            );
        } else {
            BankInterface(fToken).repayBorrow(amount);
        }
    }

    function withdraw(
        address fToken,
        address fNativeToken,
        uint256 amount,
        address caller
    ) external {
        _byClient();

        BankInterface(fToken).redeemUnderlying(amount);

        if (fToken == fNativeToken) {
            payable(caller).transfer(amount);
        } else {
            IERC20(IFildaToken(fToken).underlying()).transfer(caller, amount);
        }
    }

    function _byClient() private view {
        require(
            hasRole(CLIENT, msg.sender) || hasRole(CALLER, msg.sender),
            "wrong role"
        );
    }
}
