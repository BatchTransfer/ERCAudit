"""ERCAudit: specification-guided auditing of ERC standard implementations.

Two analyzers share one Solidity front-end (:mod:`ercaudit.solidity`):

* :mod:`ercaudit.batchaudit` -- ERC-1155 batch-transfer constraint checking
  (static) and :mod:`ercaudit.txaudit` -- on-chain transaction validation.
* :mod:`ercaudit.domaudit`   -- EIP-712 / ERC-2612 signature-domain checking.
"""
__version__ = "0.1.0"
