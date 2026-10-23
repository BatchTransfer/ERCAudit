from ercaudit.txaudit.decoding import (ZERO_ADDRESS, decode_safeBatchTransferFrom_input,
                                       decode_setApprovalForAll_input, encode_safeBatchTransferFrom)
from ercaudit.txaudit.patterns import analyse_transactions

OWNER = "0x" + "a1" * 20
OP1, OP2, OP3 = ("0x" + c * 40 for c in "bcd")
ATTACKER = "0x" + "e" * 40
BATCH = "safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)"
APPROVE = "setApprovalForAll(address,bool)"


def _approval_input(operator, approved=True):
    return "0xa22cb465" + operator[2:].rjust(64, "0") + format(int(approved), "064x")


def _batch(caller, frm, to, ids, amounts, ts=100, block=10):
    return {"functionName": BATCH, "from": caller, "input": encode_safeBatchTransferFrom(frm, to, ids, amounts),
            "timeStamp": ts, "blockNumber": block, "hash": f"0x{ts}"}


def _approve(owner, operator, ts, block, approved=True):
    return {"functionName": APPROVE, "from": owner, "input": _approval_input(operator, approved),
            "timeStamp": ts, "blockNumber": block, "hash": f"0xa{ts}"}


def test_decode_roundtrip():
    data = encode_safeBatchTransferFrom(OWNER, OP1, [1, 2, 3], [50, 50])
    frm, to, ids, amts = decode_safeBatchTransferFrom_input(data)
    assert (frm, to, ids, amts) == (OWNER, OP1, [1, 2, 3], [50, 50])
    assert decode_setApprovalForAll_input(_approval_input(OP1)) == (OP1, True)


def test_three_calldata_patterns():
    df = analyse_transactions([
        _batch(OWNER, OWNER, ZERO_ADDRESS, [1], [1]),          # zero address
        _batch(OWNER, OWNER, OP1, [1, 2, 3], [50, 50]),        # length mismatch (paper Sec. VI-B example)
        _batch(ATTACKER, OWNER, OP1, [1], [1]),                # caller not from, no approval
        _batch(OWNER, OWNER, OP1, [1], [1]),                   # benign
    ])
    assert list(df.zero_address) == [True, False, False, False]
    assert list(df.length_mismatch) == [False, True, False, False]
    assert list(df.unauthorized) == [False, False, True, False]


def test_approved_operator_is_not_unauthorized():
    df = analyse_transactions([_approve(OWNER, OP1, 50, 5), _batch(OP1, OWNER, OP2, [1], [1])])
    assert not df.unauthorized.any()


def test_published_authorization_is_permissive_and_strict_mode_is_not():
    # OP1 was approved by *someone else*; the published logic accepts any approval naming the caller.
    txs = [_approve("0x" + "9" * 40, OP1, 50, 5), _batch(OP1, OWNER, OP2, [1], [1])]
    assert not analyse_transactions(txs).unauthorized.any()
    assert analyse_transactions(txs, strict_authorization=True).unauthorized.any()


def test_secondary_approval_chain():
    txs = [_approve(OWNER, OP1, 10, 1), _approve(OP1, OP2, 20, 2), _approve(OP2, OP3, 30, 3)]
    df = analyse_transactions(txs)
    first = df.iloc[0]
    assert bool(first.operator_provides_further_approvals)
    assert first.approval_chain_depth == 2 and first.total_chain_approvals == 2
    assert not bool(df.iloc[2].operator_provides_further_approvals)
