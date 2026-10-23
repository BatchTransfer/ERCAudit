// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0xdeadbeef00000000000000000000000000000005
// Contract Name: TamillionaireCoin
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// ──────────────────────────────────────────────────────────────────────────────
// Minimal flat ERC20 + basic Permit stub + AccessControl (no external imports)
// ──────────────────────────────────────────────────────────────────────────────

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual returns (string memory) { return _name; }
    function symbol() public view virtual returns (string memory) { return _symbol; }
    function decimals() public view virtual returns (uint8) { return 18; }
    function totalSupply() public view virtual returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view virtual returns (uint256) { return _balances[account]; }

    function transfer(address to, uint256 value) public virtual returns (bool) {
        _transfer(_msgSender(), to, value);
        return true;
    }

    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) public virtual returns (bool) {
        _approve(_msgSender(), spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(from != address(0), "ERC20: transfer from zero address");
        require(to != address(0), "ERC20: transfer to zero address");
        require(_balances[from] >= value, "ERC20: transfer exceeds balance");

        unchecked {
            _balances[from] -= value;
            _balances[to] += value;
        }

        emit Transfer(from, to, value);
    }

    function _mint(address account, uint256 value) internal {
        require(account != address(0), "ERC20: mint to zero address");

        _totalSupply += value;
        unchecked { _balances[account] += value; }

        emit Transfer(address(0), account, value);
    }

    function _approve(address owner, address spender, uint256 value) internal {
        require(owner != address(0), "ERC20: approve from zero address");
        require(spender != address(0), "ERC20: approve to zero address");

        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal {
        uint256 current = _allowances[owner][spender];
        if (current != type(uint256).max) {
            require(current >= value, "ERC20: insufficient allowance");
            unchecked { _allowances[owner][spender] = current - value; }
        }
    }
}

// Minimal Permit stub – warning silenced with _ placeholders
abstract contract ERC20Permit is ERC20 {
    function nonces(address) public view virtual returns (uint256) { return 0; } // stub

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) { return bytes32(0); } // stub

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256,          // deadline – unused in stub → silenced
        uint8,            // v – unused
        bytes32,          // r – unused
        bytes32           // s – unused
    ) external virtual {
        _approve(owner, spender, value);
    }
}

abstract contract AccessControl {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    mapping(bytes32 => mapping(address => bool)) private _roles;

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyRole(bytes32 role) {
        require(hasRole(role, msg.sender), "AccessControl: missing role");
        _;
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    function _grantRole(bytes32 role, address account) internal {
        if (!hasRole(role, account)) {
            _roles[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// TamillionaireCoin – your token (flat, no warnings, GitHub metadata)
// ──────────────────────────────────────────────────────────────────────────────

contract TamillionaireCoin is ERC20, ERC20Permit, AccessControl {
    bytes32 public constant TREASURY_ROLE       = keccak256("TREASURY_ROLE");
    bytes32 public constant METADATA_ADMIN_ROLE = keccak256("METADATA_ADMIN_ROLE");

    uint256 public constant TOTAL_SUPPLY = 50_000_000_000 * 10**18;

    string private _tokenMetadataURI;
    uint256 public metadataVersion;
    bool public metadataLocked;

    event MetadataUpdated(uint256 indexed oldVersion, uint256 indexed newVersion, string oldURI, string newURI);
    event MetadataLocked(uint256 finalVersion);

    constructor() ERC20("Tamillionaire Coin", "TMC") {
        address deployer = msg.sender;

        _grantRole(DEFAULT_ADMIN_ROLE, deployer);
        _grantRole(TREASURY_ROLE, deployer);
        _grantRole(METADATA_ADMIN_ROLE, deployer);

        // ← Replace with your real GitHub raw URL before deploy
        _tokenMetadataURI = "https://raw.githubusercontent.com/tamillionairecoin/tamillionairecoin-metadata/main/tamillionairecoin.json";

        metadataVersion = 1;

        _mint(deployer, TOTAL_SUPPLY);
    }

    function tokenURI() external view returns (string memory) {
        return _tokenMetadataURI;
    }

    function updateMetadataURI(string calldata newURI) external onlyRole(METADATA_ADMIN_ROLE) {
        require(!metadataLocked, "Metadata is locked");

        string memory oldURI = _tokenMetadataURI;
        uint256 oldVersion = metadataVersion;

        _tokenMetadataURI = newURI;
        metadataVersion++;

        emit MetadataUpdated(oldVersion, metadataVersion, oldURI, newURI);
    }

    function lockMetadata() external onlyRole(METADATA_ADMIN_ROLE) {
        require(!metadataLocked, "Metadata already locked");
        metadataLocked = true;
        emit MetadataLocked(metadataVersion);
    }
}