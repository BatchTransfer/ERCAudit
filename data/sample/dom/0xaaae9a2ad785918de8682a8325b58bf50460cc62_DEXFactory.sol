// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0xaaae9a2ad785918de8682a8325b58bf50460cc62
// Contract Name: DEXFactory



// ============================================================
// FILE: contracts/core/DEXFactory.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IDEXFactory.sol";
import "../interfaces/IDEXPair.sol";
import "./SimplePair.sol";

contract DEXFactory is IDEXFactory {
    address public feeTo;
    address public feeToSetter;
    
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'DEX: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'DEX: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'DEX: PAIR_EXISTS');
        
        // Create pair using CREATE2 with salt
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        
        // Deploy DEXPair contract
        pair = deployPair(salt);
        
        // Initialize the pair
        IDEXPair(pair).initialize(token0, token1);
        
        // Store the pair mapping
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
    
    function deployPair(bytes32 salt) internal returns (address pair) {
        // Deploy a minimal pair contract for testing
        // This creates a simple proxy that delegates to an implementation
        pair = address(new SimplePair{salt: salt}());
        require(pair != address(0), 'DEX: PAIR_CREATION_FAILED');
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'DEX: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'DEX: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
} 


// ============================================================
// FILE: contracts/core/SimplePair.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IDEXPair.sol";
import "../interfaces/IERC20.sol";

contract SimplePair is IDEXPair {
    address public factory;
    address public token0;
    address public token1;
    
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;
    
    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast;
    
    uint private unlocked = 1;
    
    string public constant name = 'DEX LP Token';
    string public constant symbol = 'DEX-LP';
    uint8 public constant decimals = 18;
    uint public totalSupply;
    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;
    
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public nonces;
    
    constructor() {
        factory = msg.sender;
        uint chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }
    
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, 'DEX: FORBIDDEN');
        token0 = _token0;
        token1 = _token1;
    }
    
    function MINIMUM_LIQUIDITY() external pure returns (uint) {
        return 1000;
    }
    
    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }
    
    function mint(address to) external returns (uint liquidity) {
        // Get current token balances
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        
        // If this is the first liquidity, return a fixed amount
        if (totalSupply == 0) {
            liquidity = 1000 * 10**18; // Return 1000 tokens
        } else {
            // Calculate liquidity based on token amounts
            liquidity = (balance0 * totalSupply) / (reserve0 > 0 ? reserve0 : 1);
        }
        
        // Update reserves
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);
        
        // Mint LP tokens
        totalSupply += liquidity;
        balanceOf[to] += liquidity;
        emit Transfer(address(0), to, liquidity);
        emit Sync(reserve0, reserve1);
    }
    
    function burn(address to) external returns (uint amount0, uint amount1) {
        // Get current token balances
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        
        // Calculate proportional amounts
        uint lpBalance = balanceOf[address(this)]; // LP tokens sent to this contract
        if (totalSupply > 0) {
            amount0 = (lpBalance * balance0) / totalSupply;
            amount1 = (lpBalance * balance1) / totalSupply;
        }
        
        require(amount0 > 0 && amount1 > 0, 'DEX: INSUFFICIENT_LIQUIDITY_BURNED');
        
        // Transfer tokens to recipient
        IERC20(token0).transfer(to, amount0);
        IERC20(token1).transfer(to, amount1);
        
        // Update reserves
        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);
        
        // Burn LP tokens
        totalSupply -= lpBalance;
        balanceOf[address(this)] = 0;
        emit Transfer(address(this), address(0), lpBalance);
        emit Sync(reserve0, reserve1);
    }
    
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external {
        require(amount0Out > 0 || amount1Out > 0, 'DEX: INSUFFICIENT_OUTPUT_AMOUNT');
        require(amount0Out < reserve0 && amount1Out < reserve1, 'DEX: INSUFFICIENT_LIQUIDITY');
        
        // Transfer tokens to recipient
        if (amount0Out > 0) {
            IERC20(token0).transfer(to, amount0Out);
        }
        if (amount1Out > 0) {
            IERC20(token1).transfer(to, amount1Out);
        }
        
        // Update reserves
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        
        uint amount0In = balance0 > reserve0 - amount0Out ? balance0 - (reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > reserve1 - amount1Out ? balance1 - (reserve1 - amount1Out) : 0;
        
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);
        
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
        emit Sync(reserve0, reserve1);
    }
    
    function skim(address to) external {}
    function sync() external {
        // Update reserves to match current balances
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);
        emit Sync(reserve0, reserve1);
    }
    
    function approve(address spender, uint value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }
    
    function transfer(address to, uint value) external returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }
    
    function transferFrom(address from, address to, uint value) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint).max) {
            allowance[from][msg.sender] -= value;
        }
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        return true;
    }
    
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        // Simplified permit function for testing
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }
} 


// ============================================================
// FILE: contracts/interfaces/IDEXFactory.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IDEXFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
} 


// ============================================================
// FILE: contracts/interfaces/IDEXPair.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IDEXPair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
} 


// ============================================================
// FILE: contracts/interfaces/IERC20.sol
// ============================================================
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
} 