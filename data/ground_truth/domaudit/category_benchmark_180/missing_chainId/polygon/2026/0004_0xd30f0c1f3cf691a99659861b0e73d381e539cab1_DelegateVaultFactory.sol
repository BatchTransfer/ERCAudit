// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0xd30f0c1f3cf691a99659861b0e73d381e539cab1
// Contract Name: DelegateVaultFactory
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// =========================================================================
//  Interfaces
// =========================================================================

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IERC1155 {
    function setApprovalForAll(address operator, bool approved) external;
    function isApprovedForAll(address account, address operator) external view returns (bool);
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
}

interface IERC721 {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IERC1271 {
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4);
}

interface IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4);
}

interface IVaultNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
}

// =========================================================================
//  ReentrancyGuard
// =========================================================================

abstract contract ReentrancyGuard {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;
    uint256 private _status;

    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    modifier nonReentrant() {
        if (_status == ENTERED) revert ReentrancyGuardReentrantCall();
        _status = ENTERED;
        _;
        _status = NOT_ENTERED;
    }
}

// =========================================================================
//  VaultNFT
// =========================================================================

contract VaultNFT {
    string public name = "DrPoly Vault Key";
    string public symbol = "VAULTKEY";

    address public immutable factory;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    mapping(uint256 => address) public tokenToVault;
    mapping(address => uint256) public vaultToToken;

    uint256 private _totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    error NotFactory();
    error NotOwnerOrApproved();
    error ZeroAddress();
    error TokenAlreadyMinted();
    error NonexistentToken();

    modifier onlyFactory() {
        if (msg.sender != factory) revert NotFactory();
        _;
    }

    constructor() {
        factory = msg.sender;
    }

    function mint(address to, address vault, uint256 tokenId) external onlyFactory {
        if (to == address(0)) revert ZeroAddress();
        if (_owners[tokenId] != address(0)) revert TokenAlreadyMinted();

        _owners[tokenId] = to;
        _balances[to]++;
        tokenToVault[tokenId] = vault;
        vaultToToken[vault] = tokenId;
        _totalSupply++;

        emit Transfer(address(0), to, tokenId);
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _owners[tokenId];
        if (owner == address(0)) revert NonexistentToken();
        return owner;
    }

    function balanceOf(address owner) public view returns (uint256) {
        if (owner == address(0)) revert ZeroAddress();
        return _balances[owner];
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function approve(address to, uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        if (msg.sender != owner && !_operatorApprovals[owner][msg.sender]) revert NotOwnerOrApproved();
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        ownerOf(tokenId);
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        if (to == address(0)) revert ZeroAddress();
        address owner = ownerOf(tokenId);
        if (owner != from) revert NotOwnerOrApproved();
        if (msg.sender != owner && msg.sender != getApproved(tokenId) && !isApprovedForAll(owner, msg.sender)) {
            revert NotOwnerOrApproved();
        }

        delete _tokenApprovals[tokenId];
        _balances[owner]--;
        _balances[to]++;
        _owners[tokenId] = to;

        emit Transfer(owner, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        if (to.code.length > 0) {
            bytes4 retval = IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data);
            require(retval == IERC721Receiver.onERC721Received.selector, "ERC721: unsafe recipient");
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == 0x80ac58cd || // ERC721
            interfaceId == 0x5b5e139f || // ERC721Metadata
            interfaceId == 0x01ffc9a7;   // ERC165
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        ownerOf(tokenId);
        return string(abi.encodePacked("https://drpoly.xyz/nft/", _toString(tokenId)));
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}

// =========================================================================
//  DelegateVault
// =========================================================================

contract DelegateVault is IERC1271, ReentrancyGuard {
    bytes4 constant EIP1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 constant EIP1271_INVALID = 0xffffffff;

    uint256 constant SECP256K1N_HALF = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    bytes32 public constant WITHDRAW_REQUEST_TYPEHASH =
        keccak256("WithdrawRequest(uint256 amount,address to,uint256 deadline,uint256 nonce)");
    bytes32 private immutable _DOMAIN_SEPARATOR;
    mapping(address => uint256) public withdrawNonces;

    address public constant USDC_E = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address public constant CTF_EXCHANGE = 0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E;
    address public constant NEG_RISK_EXCHANGE = 0xC5d563A36AE78145C45a50134d48A1215220f80a;
    address public constant NEG_RISK_ADAPTER = 0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296;
    address public constant CTF_CONTRACT = 0x4D97DCd97eC945f40cF65F87097ACe5EA0476045;

    address public immutable owner;
    address public immutable nftContract;
    uint256 public immutable nftTokenId;
    address public delegate;
    bool public delegateActive;
    bool public frozen;

    mapping(address => bool) public whitelistedContracts;

    event DelegateSet(address indexed oldDelegate, address indexed newDelegate);
    event DelegateRevoked(address indexed delegate);
    event DelegateActivated(address indexed delegate);
    event VaultFrozen(address indexed owner);
    event VaultUnfrozen(address indexed owner);
    event Deposited(address indexed from, uint256 amount);
    event NFTWithdrawn(address indexed owner, address indexed nftContract, uint256 indexed tokenId);
    event Withdrawn(address indexed owner, uint256 amount);
    event WithdrawnTo(address indexed owner, address indexed to, uint256 amount);
    event TokenWithdrawn(address indexed owner, address indexed token, uint256 amount);
    event ConditionalTokenWithdrawn(address indexed owner, uint256 indexed tokenId, uint256 amount);
    event ApprovalsConfigured(address indexed vault);

    error NotOwner();
    error NotOwnerOrDelegate();
    error NotDelegate();
    error VaultIsFrozen();
    error DelegateNotActive();
    error NotWhitelisted(address target);
    error ZeroAddress();
    error TransferFailed();
    error InsufficientBalance();
    error ZeroAmount();
    error InvalidContract(address addr);
    error NotNFTOwner();
    error SignatureExpired();
    error NonceMismatch();
    error InvalidSignature();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyOwnerOrDelegate() {
        if (msg.sender != owner && msg.sender != delegate) revert NotOwnerOrDelegate();
        _;
    }

    modifier onlyDelegate() {
        if (msg.sender != delegate) revert NotDelegate();
        _;
    }

    modifier whenNotFrozen() {
        if (frozen) revert VaultIsFrozen();
        _;
    }

    modifier onlyWhitelisted(address target) {
        if (!whitelistedContracts[target]) revert NotWhitelisted(target);
        _;
    }

    constructor(address _owner, address _delegate, address _nftContract, uint256 _nftTokenId) {
        if (_owner == address(0)) revert ZeroAddress();
        if (_delegate == address(0)) revert ZeroAddress();

        if (USDC_E.code.length == 0) revert InvalidContract(USDC_E);
        if (CTF_EXCHANGE.code.length == 0) revert InvalidContract(CTF_EXCHANGE);
        if (NEG_RISK_EXCHANGE.code.length == 0) revert InvalidContract(NEG_RISK_EXCHANGE);
        if (NEG_RISK_ADAPTER.code.length == 0) revert InvalidContract(NEG_RISK_ADAPTER);
        if (CTF_CONTRACT.code.length == 0) revert InvalidContract(CTF_CONTRACT);

        owner = _owner;
        nftContract = _nftContract;
        nftTokenId = _nftTokenId;
        delegate = _delegate;
        delegateActive = true;

        whitelistedContracts[CTF_EXCHANGE] = true;
        whitelistedContracts[NEG_RISK_EXCHANGE] = true;
        whitelistedContracts[NEG_RISK_ADAPTER] = true;
        whitelistedContracts[CTF_CONTRACT] = true;
        whitelistedContracts[USDC_E] = true;

        _DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,address verifyingContract)"),
            keccak256("DrPoly"),
            keccak256("1"),
            address(this)
        ));
    }

    function isValidSignature(
        bytes32 hash,
        bytes memory signature
    ) external view override returns (bytes4) {
        if (!delegateActive || frozen) return EIP1271_INVALID;
        if (signature.length != 65) return EIP1271_INVALID;

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        if (uint256(s) > SECP256K1N_HALF) return EIP1271_INVALID;
        if (v < 27) v += 27;
        if (v != 27 && v != 28) return EIP1271_INVALID;

        address signer = ecrecover(hash, v, r, s);
        if (signer == delegate) return EIP1271_MAGIC_VALUE;
        if (signer == owner) return EIP1271_MAGIC_VALUE;

        return EIP1271_INVALID;
    }

    function configureApprovals() external onlyOwnerOrDelegate {
        uint256 maxApproval = type(uint256).max;

        IERC20(USDC_E).approve(CTF_EXCHANGE, maxApproval);
        IERC20(USDC_E).approve(NEG_RISK_EXCHANGE, maxApproval);
        IERC20(USDC_E).approve(NEG_RISK_ADAPTER, maxApproval);
        IERC20(USDC_E).approve(CTF_CONTRACT, maxApproval);

        IERC1155(CTF_CONTRACT).setApprovalForAll(CTF_EXCHANGE, true);
        IERC1155(CTF_CONTRACT).setApprovalForAll(NEG_RISK_EXCHANGE, true);
        IERC1155(CTF_CONTRACT).setApprovalForAll(NEG_RISK_ADAPTER, true);

        emit ApprovalsConfigured(address(this));
    }

    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        bool success = IERC20(USDC_E).transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();
        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        uint256 balance = IERC20(USDC_E).balanceOf(address(this));
        if (amount > balance) revert InsufficientBalance();
        bool success = IERC20(USDC_E).transfer(owner, amount);
        if (!success) revert TransferFailed();
        emit Withdrawn(owner, amount);
    }

    function withdrawTo(uint256 amount, address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        uint256 balance = IERC20(USDC_E).balanceOf(address(this));
        if (amount > balance) revert InsufficientBalance();
        bool success = IERC20(USDC_E).transfer(to, amount);
        if (!success) revert TransferFailed();
        emit WithdrawnTo(owner, to, amount);
    }

    function withdrawAll() external onlyOwner nonReentrant {
        uint256 balance = IERC20(USDC_E).balanceOf(address(this));
        if (balance > 0) {
            bool success = IERC20(USDC_E).transfer(owner, balance);
            if (!success) revert TransferFailed();
            emit Withdrawn(owner, balance);
        }
    }

    function withdrawBySig(
        uint256 amount,
        address to,
        uint256 deadline,
        uint256 nonce,
        bytes calldata signature
    ) external nonReentrant whenNotFrozen {
        if (amount == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();
        if (block.timestamp > deadline) revert SignatureExpired();
        if (nonce != withdrawNonces[owner]) revert NonceMismatch();

        bytes32 structHash = keccak256(abi.encode(
            WITHDRAW_REQUEST_TYPEHASH,
            amount,
            to,
            deadline,
            nonce
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _DOMAIN_SEPARATOR, structHash));

        address signer = _recoverSigner(digest, signature);
        if (signer != owner) revert NotOwner();

        withdrawNonces[owner]++;

        uint256 balance = IERC20(USDC_E).balanceOf(address(this));
        if (amount > balance) revert InsufficientBalance();

        bool success = IERC20(USDC_E).transfer(to, amount);
        if (!success) revert TransferFailed();

        emit WithdrawnTo(owner, to, amount);
    }

    function getWithdrawNonce() external view returns (uint256) {
        return withdrawNonces[owner];
    }

    function getDomainSeparator() external view returns (bytes32) {
        return _DOMAIN_SEPARATOR;
    }

    function withdrawToken(address token, uint256 amount) external onlyOwner nonReentrant {
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (amount > bal) revert InsufficientBalance();
        bool success = IERC20(token).transfer(owner, amount);
        if (!success) revert TransferFailed();
        emit TokenWithdrawn(owner, token, amount);
    }

    function withdrawByNFT(uint256 amount, address to) external nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (IVaultNFT(nftContract).ownerOf(nftTokenId) != msg.sender) revert NotNFTOwner();

        uint256 balance = IERC20(USDC_E).balanceOf(address(this));
        uint256 transferAmount = (amount == type(uint256).max) ? balance : amount;
        if (transferAmount == 0) revert ZeroAmount();
        if (transferAmount > balance) revert InsufficientBalance();

        bool success = IERC20(USDC_E).transfer(to, transferAmount);
        if (!success) revert TransferFailed();
        emit WithdrawnTo(owner, to, transferAmount);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function withdrawNFT(address _nftContract, uint256 tokenId) external onlyOwner nonReentrant {
        IERC721(_nftContract).safeTransferFrom(address(this), owner, tokenId);
        emit NFTWithdrawn(owner, _nftContract, tokenId);
    }

    function withdrawConditionalToken(uint256 tokenId, uint256 amount) external onlyOwner nonReentrant {
        IERC1155(CTF_CONTRACT).safeTransferFrom(address(this), owner, tokenId, amount, "");
        emit ConditionalTokenWithdrawn(owner, tokenId, amount);
    }

    function setDelegate(address _delegate) external onlyOwner {
        if (_delegate == address(0)) revert ZeroAddress();
        address oldDelegate = delegate;
        delegate = _delegate;
        delegateActive = true;
        emit DelegateSet(oldDelegate, _delegate);
    }

    function revokeDelegate() external onlyOwner {
        delegateActive = false;
        emit DelegateRevoked(delegate);
    }

    function activateDelegate() external onlyOwner {
        delegateActive = true;
        emit DelegateActivated(delegate);
    }

    function freeze() external onlyOwner {
        frozen = true;
        emit VaultFrozen(owner);
    }

    function unfreeze() external onlyOwner {
        frozen = false;
        emit VaultUnfrozen(owner);
    }

    function getVaultBalance() external view returns (uint256) {
        return IERC20(USDC_E).balanceOf(address(this));
    }

    function getConditionalTokenBalance(uint256 tokenId) external view returns (uint256) {
        return IERC1155(CTF_CONTRACT).balanceOf(address(this), tokenId);
    }

    function getVaultInfo() external view returns (
        address _owner,
        address _delegate,
        bool _delegateActive,
        bool _frozen,
        uint256 _usdcBalance
    ) {
        return (
            owner,
            delegate,
            delegateActive,
            frozen,
            IERC20(USDC_E).balanceOf(address(this))
        );
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
        interfaceId == type(IERC1271).interfaceId ||
        interfaceId == 0x4e2312e0 ||
        interfaceId == 0x150b7a02 ||
        interfaceId == 0x01ffc9a7;
    }

    function _recoverSigner(bytes32 digest, bytes calldata signature) internal pure returns (address) {
        if (signature.length != 65) revert InvalidSignature();

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        if (uint256(s) > SECP256K1N_HALF) revert InvalidSignature();
        if (v < 27) v += 27;
        if (v != 27 && v != 28) revert InvalidSignature();

        address recovered = ecrecover(digest, v, r, s);
        if (recovered == address(0)) revert InvalidSignature();
        return recovered;
    }

    receive() external payable {}
}

// =========================================================================
//  DelegateVaultFactory
// =========================================================================

contract DelegateVaultFactory {

    address public owner;

    mapping(address => bool) public operators;

    address public immutable vaultNFT;

    mapping(address => address) public userVaults;
    mapping(address => bool) public isVault;
    address[] public allVaults;

    event VaultCreated(
        address indexed owner,
        address indexed delegate,
        address indexed vault
    );

    event OperatorAdded(address indexed operator);
    event OperatorRemoved(address indexed operator);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error NotAuthorized();
    error ZeroAddress();
    error VaultAlreadyExists(address owner, address existingVault);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyAuthorized() {
        if (msg.sender != owner && !operators[msg.sender]) revert NotAuthorized();
        _;
    }

    constructor() {
        owner = msg.sender;
        vaultNFT = address(new VaultNFT());
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        if (_newOwner == address(0)) revert ZeroAddress();

        address oldOwner = owner;
        owner = _newOwner;

        emit OwnershipTransferred(oldOwner, _newOwner);
    }

    function addOperator(address _operator) external onlyOwner {
        if (_operator == address(0)) revert ZeroAddress();

        operators[_operator] = true;
        emit OperatorAdded(_operator);
    }

    function removeOperator(address _operator) external onlyOwner {
        operators[_operator] = false;
        emit OperatorRemoved(_operator);
    }

    function createVault(
        address _owner,
        address _delegate
    ) external onlyAuthorized returns (address vault) {

        if (_owner == address(0) || _delegate == address(0)) revert ZeroAddress();

        if (userVaults[_owner] != address(0)) {
            revert VaultAlreadyExists(_owner, userVaults[_owner]);
        }

        uint256 tokenId = allVaults.length;
        bytes32 salt = keccak256(abi.encodePacked(_owner, _delegate));

        vault = address(
            new DelegateVault{salt: salt}(
                _owner,
                _delegate,
                vaultNFT,
                tokenId
            )
        );

        userVaults[_owner] = vault;
        isVault[vault] = true;
        allVaults.push(vault);

        VaultNFT(vaultNFT).mint(_owner, vault, tokenId);

        emit VaultCreated(_owner, _delegate, vault);
    }

    function getVaultAddress(
        address _owner,
        address _delegate,
        uint256 _tokenId
    ) external view returns (address) {

        bytes32 salt = keccak256(abi.encodePacked(_owner, _delegate));

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(
                    abi.encodePacked(
                        type(DelegateVault).creationCode,
                        abi.encode(_owner, _delegate, vaultNFT, _tokenId)
                    )
                )
            )
        );

        return address(uint160(uint256(hash)));
    }

    function getVaultCount() external view returns (uint256) {
        return allVaults.length;
    }

    function getUserVault(address _owner) external view returns (address) {
        return userVaults[_owner];
    }
}