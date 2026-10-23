// SPDX-License-Identifier: UNLICENSED
// Flattened source downloaded from Etherscan
// Address: 0x2216570569d31a42fb8cf4746413fdb3c970d39e
// Contract Name: ParagonPair



// ============================================================
// FILE: @openzeppelin/contracts/token/ERC20/IERC20.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC20/IERC20.sol)

pragma solidity >=0.4.16;

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}



// ============================================================
// FILE: @openzeppelin/contracts/utils/ReentrancyGuard.sol
// ============================================================
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/ReentrancyGuard.sol)

pragma solidity ^0.8.20;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If EIP-1153 (transient storage) is available on the chain you're deploying at,
 * consider using {ReentrancyGuardTransient} instead.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}



// ============================================================
// FILE: audit/contracts/exchange/interfaces/IParagonCallee.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

/**
 * @title IParagonCallee
 * @dev Interface for Paragon flash loan callbacks
 */
interface IParagonCallee {
    function paragonCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}



// ============================================================
// FILE: audit/contracts/exchange/interfaces/IParagonFactory.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

/**
 * @title IParagonFactory
 * @dev Interface for the Paragon Factory contract
 */
interface IParagonFactory {
    // Core events
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);
    event FeeToUpdated(address indexed feeTo);
    event FeeToSetterUpdated(address indexed feeToSetter);
    event SwapFeeUpdated(uint32 swapFeeBips);

    // XPGN config (used by ParagonLibrary pause-guard)
    event XPGNTokenUpdated(address indexed xpgn);

    // Views
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function swapFeeBips() external view returns (uint32);
    function xpgnToken() external view returns (address);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint256) external view returns (address pair);
    function allPairsLength() external view returns (uint256);
    function INIT_CODE_PAIR_HASH() external view returns (bytes32);
    function getEffectiveSwapFeeBips(address pair) external view returns (uint32);
    function calculateInitialPairFeeBips(address tokenA, address tokenB) external view returns (uint32 bips, uint8 category);

    // Mutations
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
    function setSwapFee(uint32) external;
    function setXPGNToken(address _xpgnToken) external;
    function setPairSwapFee(address pair, uint32 bips) external;
    function setDefaultNonBaseFees(uint32 nonBaseWithBaseFeeBips, uint32 nonBaseFeeBips) external;
    function setBaseToken(address token, bool isBase) external;
    function setBaseTokens(address[] calldata tokens, bool[] calldata flags) external;
    function setPairAllowlist(address tokenA, address tokenB, bool allowed) external;
    function clearPairSwapFee(address pair) external;
}



// ============================================================
// FILE: audit/contracts/exchange/interfaces/IParagonPair.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

/**
 * @title IParagonPair
 * @notice Interface for Paragon (UniV2-style) liquidity pair
 * @dev ABI matches ParagonPair exactly. `getReserves` returns a tuple (not a struct).
 */
interface IParagonPair {
    // ─────────────────────────────
    // Events
    // ─────────────────────────────

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    // ─────────────────────────────
    // Immutable / public views
    // ─────────────────────────────

    function MINIMUM_LIQUIDITY() external pure returns (uint256);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    // ─────────────────────────────
    // Core actions
    // ─────────────────────────────

    function mint(address to) external returns (uint256 liquidity);

    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function skim(address to) external;

    function sync() external;

    function initialize(address _token0, address _token1) external;
}



// ============================================================
// FILE: audit/contracts/exchange/libraries/Math.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

/**
 * @title Math
 * @dev A library for mathematical operations used in Paragon protocol
 */
library Math {
    // Computes the square root of a number using the Babylonian method
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    // Returns the minimum of two numbers
    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x <= y ? x : y;
    }
}



// ============================================================
// FILE: audit/contracts/exchange/libraries/UQ112x112.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

/**
 * @title UQ112x112
 * @dev A library for handling binary fixed point numbers (https://en.wikipedia.org/wiki/Q_(number_format))
 * @notice Range: [0, 2**112 - 1], Resolution: 1 / 2**112
 */
library UQ112x112 {
    uint224 constant Q112 = 2**112;

    // Encode a uint112 as a UQ112x112
    function encode(uint112 y) internal pure returns (uint224 z) {
        z = uint224(y) * Q112; // never overflows
    }

    // Divide a UQ112x112 by a uint112, returning a UQ112x112
    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}



// ============================================================
// FILE: audit/contracts/exchange/ParagonERC20.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

import "./interfaces/IParagonPair.sol";

/**
 * @title ParagonERC20
 * @dev ERC20 implementation for Paragon LP tokens with EIP-712 permit functionality
 *      PAD-26 FIX: DOMAIN_SEPARATOR refreshes if chainId changes.
 *      PAD-37 FIX: Disallow transfers to address(0) to prevent accidental burning.
 */
contract ParagonERC20 {
    string public constant name = "Paragon LPs";
    string public constant symbol = "XPGN-LP";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // -------- EIP-712 / Permit --------
    bytes32 private constant _EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    mapping(address => uint256) public nonces;

    // PAD-26: cache + refresh pattern
    uint256 private immutable _INITIAL_CHAIN_ID;
    bytes32 private immutable _INITIAL_DOMAIN_SEPARATOR;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor() {
        _INITIAL_CHAIN_ID = block.chainid;
        _INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator(block.chainid);
    }

    function _computeDomainSeparator(uint256 chainId) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                _EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    /// @notice EIP-712 domain separator (refreshes automatically if chainId changes)
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == _INITIAL_CHAIN_ID
            ? _INITIAL_DOMAIN_SEPARATOR
            : _computeDomainSeparator(block.chainid);
    }

    function _mint(address to, uint256 value) internal {
        require(to != address(0), "Paragon: MINT_TO_ZERO"); // (recommended hardening)
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        // burn to zero is intended behavior
        balanceOf[from] -= value;
        totalSupply -= value;
        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint256 value) private {
        require(owner != address(0), "Paragon: APPROVE_FROM_ZERO"); // optional hardening
        require(spender != address(0), "Paragon: APPROVE_TO_ZERO"); // optional hardening
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint256 value) private {
        require(to != address(0), "Paragon: TRANSFER_TO_ZERO"); // ✅ PAD-37 FIX
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
        return true;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "Paragon: EXPIRED");

        uint256 nonce = nonces[owner]++;

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline))
            )
        );

        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, "Paragon: INVALID_SIGNATURE");

        _approve(owner, spender, value);
    }
}



// ============================================================
// FILE: audit/contracts/exchange/ParagonPair.sol
// ============================================================
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IParagonFactory.sol";
import "./interfaces/IParagonPair.sol";
import "./interfaces/IParagonCallee.sol";
import "./ParagonERC20.sol";
import "./libraries/Math.sol";
import "./libraries/UQ112x112.sol";

/**
 * @title ParagonPair
 * @dev Uniswap V2-style liquidity pool for token pairs, aligned with OZ 5.0.1
 */
contract ParagonPair is ParagonERC20, ReentrancyGuard, IParagonPair {
    using UQ112x112 for uint224;

    uint256 public constant override MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    /// @inheritdoc IParagonPair
    address public immutable override factory;
    /// @inheritdoc IParagonPair
    address public override token0;
    /// @inheritdoc IParagonPair
    address public override token1;

    // Reserves are private like UniV2; read via getReserves()
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    /// @inheritdoc IParagonPair
    uint256 public override price0CumulativeLast;
    /// @inheritdoc IParagonPair
    uint256 public override price1CumulativeLast;
    /// @inheritdoc IParagonPair
    uint256 public override kLast;

    constructor() {
        factory = msg.sender; // set by Factory via create2
    }

    /// @inheritdoc IParagonPair
    function initialize(address _token0, address _token1) external override {
        require(msg.sender == factory, "Paragon: FORBIDDEN");
        require(_token0 < _token1, "Paragon: BAD_ORDER");
        // Optional: double-check they are contracts (Factory already validates)
        require(_token0.code.length > 0 && _token1.code.length > 0, "Paragon: NOT_CONTRACT");
        token0 = _token0;
        token1 = _token1;
    }

    /// @inheritdoc IParagonPair
    function getReserves()
        public
        view
        override
        returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast)
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /// @notice Helper to read the factory’s swap fee in bips
    function getSwapFee() public view returns (uint32) {
        return IParagonFactory(factory).getEffectiveSwapFeeBips(address(this));
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(TRANSFER_SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Paragon: TRANSFER_FAILED");
    }

    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "Paragon: OVERFLOW");
        uint32 blockTime = uint32(block.timestamp);
        unchecked {
            // overflow on subtraction is OK per UniV2
            uint32 timeElapsed = blockTime - blockTimestampLast;
            if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
                price0CumulativeLast += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
                price1CumulativeLast += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
            }
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTime;
        emit Sync(reserve0, reserve1);
    }

    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IParagonFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLastLoc = kLast;

        if (feeOn && _kLastLoc != 0) {
            uint256 rootK = Math.sqrt(uint256(_reserve0) * _reserve1);
            uint256 rootKLast = Math.sqrt(_kLastLoc);

            if (rootK > rootKLast) {
                uint256 numerator = totalSupply * (rootK - rootKLast);
                uint256 denominator = rootK * 5 + rootKLast;
                uint256 liquidity = numerator / denominator;

                if (liquidity > 0) _mint(feeTo, liquidity);
            }
        } else if (!feeOn && _kLastLoc != 0) {
            kLast = 0; // Fee disabled → clear kLast (standard behavior)
        }
    }

    /// @inheritdoc IParagonPair
    function mint(address to)
        external
        override
        nonReentrant
        returns (uint256 liquidity)
    {
        (uint112 _r0, uint112 _r1,) = getReserves();
        uint256 b0 = IERC20(token0).balanceOf(address(this));
        uint256 b1 = IERC20(token1).balanceOf(address(this));
        uint256 d0 = b0 - _r0;
        uint256 d1 = b1 - _r1;

        bool feeOn = _mintFee(_r0, _r1);
        uint256 _totalSup = totalSupply;

        if (_totalSup == 0) {
            liquidity = Math.sqrt(d0 * d1) - MINIMUM_LIQUIDITY;
            _mint(address(0xdEaD), MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min((d0 * _totalSup) / _r0, (d1 * _totalSup) / _r1);
        }
        require(liquidity > 0, "Paragon: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(b0, b1, _r0, _r1);
        if (feeOn) kLast = uint256(reserve0) * reserve1;
        emit Mint(msg.sender, d0, d1);
    }

    /// @inheritdoc IParagonPair
    function burn(address to)
        external
        override
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        (uint112 _r0, uint112 _r1,) = getReserves();
        address _t0 = token0;
        address _t1 = token1;

        uint256 b0 = IERC20(_t0).balanceOf(address(this));
        uint256 b1 = IERC20(_t1).balanceOf(address(this));
        uint256 liq = balanceOf[address(this)];

        bool feeOn = _mintFee(_r0, _r1);
        uint256 _tot = totalSupply;

        amount0 = (liq * b0) / _tot;
        amount1 = (liq * b1) / _tot;
        require(amount0 > 0 && amount1 > 0, "Paragon: INSUFFICIENT_LIQUIDITY_BURNED");

        _burn(address(this), liq);
        _safeTransfer(_t0, to, amount0);
        _safeTransfer(_t1, to, amount1);

        b0 = IERC20(_t0).balanceOf(address(this));
        b1 = IERC20(_t1).balanceOf(address(this));

        _update(b0, b1, _r0, _r1);
        if (feeOn) kLast = uint256(reserve0) * reserve1;
        emit Burn(msg.sender, amount0, amount1, to);
    }

    /// @inheritdoc IParagonPair
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external override nonReentrant {
        require(amount0Out > 0 || amount1Out > 0, "Paragon: INSUFFICIENT_OUTPUT_AMOUNT");
        require(to != address(this), "Paragon: INVALID_TO_SELF");

        (uint112 _r0, uint112 _r1,) = getReserves();
        require(amount0Out < _r0 && amount1Out < _r1, "Paragon: INSUFFICIENT_LIQUIDITY");

        uint256 b0;
        uint256 b1;
        {
            address _t0 = token0;
            address _t1 = token1;
            require(to != _t0 && to != _t1, "Paragon: INVALID_TO");

            if (amount0Out > 0) _safeTransfer(_t0, to, amount0Out);
            if (amount1Out > 0) _safeTransfer(_t1, to, amount1Out);

            if (data.length > 0) {
                IParagonCallee(to).paragonCall(msg.sender, amount0Out, amount1Out, data);
            }

            b0 = IERC20(_t0).balanceOf(address(this));
            b1 = IERC20(_t1).balanceOf(address(this));
        }

        uint256 in0 = b0 > (_r0 - amount0Out) ? b0 - (_r0 - amount0Out) : 0;
        uint256 in1 = b1 > (_r1 - amount1Out) ? b1 - (_r1 - amount1Out) : 0;
        require(in0 > 0 || in1 > 0, "Paragon: INSUFFICIENT_INPUT_AMOUNT");

        uint32 fee = getSwapFee();
        {
            uint256 adj0 = b0 * 10000 - in0 * fee;
            uint256 adj1 = b1 * 10000 - in1 * fee;
            require(adj0 * adj1 >= uint256(_r0) * _r1 * 10000**2, "Paragon: K");
        }

        _update(b0, b1, _r0, _r1);
        emit Swap(msg.sender, in0, in1, amount0Out, amount1Out, to);
    }

    /// @inheritdoc IParagonPair
    function skim(address to) external override nonReentrant {
        _safeTransfer(token0, to, IERC20(token0).balanceOf(address(this)) - reserve0);
        _safeTransfer(token1, to, IERC20(token1).balanceOf(address(this)) - reserve1);
    }

    /// @inheritdoc IParagonPair
    function sync() external override nonReentrant {
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }
}
