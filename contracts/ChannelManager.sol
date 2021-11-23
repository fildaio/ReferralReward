// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "./Channel.sol";
import "./Interfaces.sol";
import "./Global.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract ChannelManager is Global, AccessControl {
    using SafeMath for uint256;

    struct TokenAmount {
        address token;
        uint256 amount;
    }

    bytes32 public constant MANAGER = keccak256("MANAGER");
    address public wrappedNativeToken;
    address public maximillion;

    mapping(address => string) public channelNames;
    mapping(string => address) public channels;

    uint16 private _denomination = 10000;
    mapping(address => mapping(address => uint16)) private _shareOfChannel; // 渠道=>币种=>分成比例
    mapping(address => mapping(address => uint256)) private _savings; // 渠道=>币种=>存款余额。
    mapping(address => TokenAmount[]) private _accShareByChannel; // 渠道=>[币种, 累积的分成]
    mapping(address => TokenAmount[]) private _accAmountByChannel; // 渠道=>[币种, 累积的投入数量]，只为记帐。

    event ChannelCreated(string channelName, address channelAddress);
    event Withdrawn(
        address indexed channelAddress,
        address receiver,
        address indexed token,
        uint256 amount
    );
    event DeleteRecords(address channelAddress);

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    receive() external payable {}

    function setWrappedNativeToken(address token) public {
        _byManagers();
        wrappedNativeToken = token;
    }

    function setMaximillion(address token) public {
        _byManagers();
        maximillion = token;
    }

    function setManager(address managerAddress) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        _setupRole(MANAGER, managerAddress);
    }

    function createChannel(string memory channelName) external {
        _byManagers();

        address channelAddress = address(new Channel());
        channelNames[channelAddress] = channelName;
        channels[channelName] = channelAddress;

        emit ChannelCreated(channelName, channelAddress);
    }

    function assignManagerForChannel(
        address payable channel,
        address channelManagerAddress
    ) external {
        _byManagers();
        Channel(channel).setAdministrator(channelManagerAddress);
    }

    function setShareRateOfChannel(
        address channel,
        address fToken,
        uint16 share
    ) external {
        _byManagers();
        _shareOfChannel[channel][fToken] = share;
    }

    function getShareRateOfChannel(address channel, address fToken)
        external
        view
        returns (uint256)
    {
        return _shareOfChannel[channel][fToken];
    }

    function triggerChannel(address payable channel, bool active) external {
        _byManagers();
        Channel(channel).trigger(active);
    }

    function setChannelMode(address payable channel, Mode mode) external {
        _byManagers();
        Channel(channel).setMode(mode);
    }

    function getShareRateByChannel(address fToken)
        external
        view
        returns (uint16 share, uint16 denomination)
    {
        share = _shareOfChannel[msg.sender][fToken];
        denomination = _denomination;
    }

    function chargeDeposit(
        address fToken,
        uint256 amount,
        bool recordAsFToken
    ) external {
        _savings[msg.sender][fToken] += amount;

        bool includes = false;

        address theToken;
        TokenAmount[] storage shares;

        if (!recordAsFToken) {
            if (fToken == wrappedNativeToken) {
                theToken = address(0);
            } else {
                theToken = IFildaToken(fToken).underlying();
            }

            shares = _accShareByChannel[msg.sender];
        } else {
            theToken = fToken;
            shares = _accAmountByChannel[msg.sender];
        }

        for (uint256 i = 0; i < shares.length; i++) {
            if (shares[i].token == theToken) {
                shares[i].amount = shares[i].amount.add(amount);
                includes = true;
                break;
            }
        }

        if (includes == false) {
            shares.push(TokenAmount({token: theToken, amount: amount}));
        }
    }

    function withdraw(address channelAdmin) external {
        TokenAmount[] storage shares = _accShareByChannel[msg.sender];
        for (uint256 i = 0; i < shares.length; i++) {
            uint256 amt = shares[i].amount;
            if (amt > 0) {
                shares[i].amount = 0;

                if (shares[i].token == address(0)) {
                    payable(channelAdmin).transfer(amt);
                } else {
                    IERC20(shares[i].token).transfer(channelAdmin, amt);
                }

                emit Withdrawn(msg.sender, channelAdmin, shares[i].token, amt);
            }
        }
    }

    function savings(address channel, address token)
        external
        view
        returns (uint256)
    {
        _byManagers();
        return _savings[channel][token];
    }

    function accShareByChannel(address channel)
        external
        view
        returns (TokenAmount[] memory accumulatedShare)
    {
        _byManagers();
        accumulatedShare = _accShareByChannel[channel];
    }

    function accAmountByChannel(address channel)
        external
        view
        returns (TokenAmount[] memory accumulatedAmount)
    {
        _byManagers();
        accumulatedAmount = _accAmountByChannel[channel];
    }

    function cleanAccAmountByChannel(address channel) public {
        _byManagers();
        delete _accAmountByChannel[channel];
        emit DeleteRecords(channel);
    }

    function _byManagers() private view {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
                hasRole(MANAGER, msg.sender),
            "wrong role"
        );
    }
}
