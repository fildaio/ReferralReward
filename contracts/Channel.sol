// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "./Agent.sol";
import "./Interfaces.sol";
import "./Global.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IChannelManager {
    function wrappedNativeToken() external returns (address);

    function maximillion() external returns (address);

    function getShareRateByChannel(address fToken)
        external
        view
        returns (uint16 share, uint16 denomination);

    function chargeDeposit(
        address fToken,
        uint256 amount,
        bool recordAsFToken
    ) external;

    function withdraw(address channelAdmin) external;
}

contract Channel is Global, AccessControl {
    using SafeMath for uint256;

    bytes32 public constant FILDA = keccak256("FILDA");
    bytes32 public constant ADMIN = keccak256("ADMIN");

    address public filda;
    mapping(address => address payable) public agent;

    Mode private _mode = Mode.tokenShare;
    bool private _actived = true;
    string private noRole = "no role";

    event DepositEvent(
        address indexed caller,
        address indexed agent,
        address indexed fToken,
        uint256 amount
    );
    event BorrowEvent(
        address indexed caller,
        address indexed agent,
        address indexed fToken,
        uint256 amount
    );
    event RepayEvent(
        address indexed caller,
        address indexed agent,
        address indexed fToken,
        uint256 amount
    );
    event UserWithdrawEvent(
        address indexed caller,
        address indexed agent,
        address indexed fToken,
        uint256 amount
    );

    constructor() {
        filda = msg.sender;
        _setupRole(FILDA, filda);
    }

    receive() external payable {}

    function setAdministrator(address admin) external {
        _byCooperate();
        _setupRole(ADMIN, admin);
    }

    function trigger(bool activedStatus) external {
        _byAdministrator();
        _actived = activedStatus;
    }

    function setMode(Mode mode) external {
        _byCooperate();
        _mode = mode;
    }

    function getMode() public view returns (Mode) {
        return _mode;
    }

    function applyAgent() public {
        require(agent[msg.sender] == address(0), "agent exists");
        agent[msg.sender] = payable(new Agent(msg.sender));
    }

    function getShareRate(address fToken)
        public
        view
        returns (uint16 shareRate, uint16 denomination)
    {
        _byAdministrator();
        (shareRate, denomination) = IChannelManager(filda)
            .getShareRateByChannel(fToken);
    }

    // 用户调用存款。
    function deposit(address fToken, uint256 transferAmount) external payable {
        _mustBeActived();

        // 取得或新建该用户的代理人。
        if (agent[msg.sender] == address(0)) {
            applyAgent();
        }

        address token;
        uint256 amount;
        if (fToken == IChannelManager(filda).wrappedNativeToken()) {
            require(msg.value >= transferAmount, "insufficient amount");

            token = address(0);
            amount = msg.value;
        } else {
            _approve(fToken, transferAmount);
            token = IFildaToken(fToken).underlying();
            amount = transferAmount;
        }

        // // 取得分成率。
        (uint16 shareRate, uint16 denomination) = getShareRate(fToken);

        if (_mode == Mode.tokenShare) {
            // 计算分成。
            uint256 share = amount.mul(shareRate).div(denomination);
            uint256 toDeposit = amount.sub(share);

            // 把当前渠道的分成转给渠道管理合约。
            if (token == address(0)) {
                payable(filda).transfer(share);

                Agent(agent[msg.sender]).deposit{value: toDeposit}(
                    fToken,
                    toDeposit
                );

                // 由渠道管理合约记帐。
                IChannelManager(filda).chargeDeposit(fToken, share, false);
            } else {
                IERC20(token).transferFrom(msg.sender, filda, share);

                // 余下的份额转给agent，以存入filda。
                IERC20(token).transferFrom(
                    msg.sender,
                    agent[msg.sender],
                    toDeposit
                );
                Agent(agent[msg.sender]).deposit(fToken, toDeposit);

                // 由渠道管理合约记帐。
                IChannelManager(filda).chargeDeposit(fToken, share, false);
            }
        }

        if (_mode == Mode.fTokenShare) {
            if (token == address(0)) {
                Agent(agent[msg.sender]).deposit{value: amount}(fToken, amount);
            } else {
                IERC20(token).transferFrom(
                    msg.sender,
                    agent[msg.sender],
                    amount
                );
                Agent(agent[msg.sender]).deposit(fToken, amount);
            }

            IChannelManager(filda).chargeDeposit(fToken, amount, true);
        }

        emit DepositEvent(msg.sender, agent[msg.sender], fToken, amount);
    }

    function userWithdraw(address fToken, uint256 amount) external {
        // 取得或新建该用户的代理人。
        if (agent[msg.sender] == address(0)) {
            applyAgent();
        }

        Agent(agent[msg.sender]).withdraw(
            fToken,
            IChannelManager(filda).wrappedNativeToken(),
            amount,
            msg.sender
        );

        emit UserWithdrawEvent(msg.sender, agent[msg.sender], fToken, amount);
    }

    function borrow(address fToken, uint256 amount) external {
        _mustBeActived();

        // 取得或新建该用户的代理人。
        if (agent[msg.sender] == address(0)) {
            applyAgent();
        }

        Agent(agent[msg.sender]).borrow(
            fToken,
            IChannelManager(filda).wrappedNativeToken(),
            amount,
            msg.sender
        );

        emit BorrowEvent(msg.sender, agent[msg.sender], fToken, amount);
    }

    function repay(address fToken, uint256 amount) external payable {
        _mustBeActived();

        // 取得或新建该用户的代理人。
        if (agent[msg.sender] == address(0)) {
            applyAgent();
        }

        if (fToken == IChannelManager(filda).wrappedNativeToken()) {
            require(msg.value >= amount, "insufficient amount");

            Agent(agent[msg.sender]).repay{value: msg.value}(
                fToken,
                IChannelManager(filda).maximillion(),
                amount
            );
        } else {
            _approve(fToken, amount);

            // 把还款金额转给agent。
            IERC20(IFildaToken(fToken).underlying()).transferFrom(
                msg.sender,
                agent[msg.sender],
                amount
            );
            Agent(agent[msg.sender]).repay(fToken, address(0), amount);
        }

        emit RepayEvent(msg.sender, agent[msg.sender], fToken, amount);
    }

    function withdraw() external {
        _byAdministrator();
        IChannelManager(filda).withdraw(msg.sender);
    }

    function _approve(address fToken, uint256 amount) private {
        require(agent[msg.sender] != address(0), "no agent");
        Agent(agent[msg.sender]).approve(
            IFildaToken(fToken).underlying(),
            fToken,
            amount
        );
    }

    function _byFilda() private view {
        require(hasRole(FILDA, msg.sender), noRole);
    }

    function _byAdministrator() private view {
        require(hasRole(ADMIN, msg.sender), noRole);
    }

    function _byCooperate() private view {
        require(
            hasRole(FILDA, msg.sender) || hasRole(ADMIN, msg.sender),
            noRole
        );
    }

    function _mustBeActived() private view {
        require(_actived == true);
    }
}
