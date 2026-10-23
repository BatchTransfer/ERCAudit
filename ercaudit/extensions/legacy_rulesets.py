"""Additional ERC rule sets from the original research script (NOT evaluated in the papers).

These functions are extracted verbatim from ``erc1155_safeBatchTransferFrom.py``
by line range; only the shared helpers are now imported from
:mod:`ercaudit.solidity` and the ERC-20 ``transferFrom`` parameter extractor was
renamed (it shadowed the batch one in the original file, see
``docs/AUDIT_REPORT.md``, finding F1). They demonstrate that the constraint
engine is not specific to ERC-1155 -- rule sets exist for ERC-3643 batch
operations, ``setApprovalForAll``, ERC-2612 ``permit``, ERC-5267 ``eip712Domain``
and ERC-20 ``transferFrom`` -- but they have not been validated against a labelled
corpus and are provided as extension points.
"""
from __future__ import annotations

import re
from typing import Dict, List

from ..solidity import extract_batch_parameters, find_all_functions, find_functions_by_signature, find_if_revert_control_flow, get_all_internal_calls


def extract_parameters(target_func: Dict) -> Dict:
    """Placeholder: the original ``verify_erc2612_requirements`` calls ``extract_parameters``,
    which is not defined anywhere in the research script (finding F2, ``docs/AUDIT_REPORT.md``).
    Returning no names makes it fall back to the conventional ERC-2612 names."""
    return {}


def extract_transferFrom_parameters(target_func: Dict) -> Dict:
    """Extract parameter names from transferFrom function."""
    params = target_func.get('parameters', {})
    param_names = params.get('names', [])

    result = {
        'from_param': param_names[0] if len(param_names) > 0 else 'from',
        'to_param': param_names[1] if len(param_names) > 1 else 'to',
        'amount_param': param_names[2] if len(param_names) > 2 else 'amount'
    }
    return result


def extract_setApprovalForAll_parameters(target_func: Dict) -> Dict:
    """Extract and return all relevant parameters from the target function."""
    params = list(target_func.get('parameters', {}).items())
    return {
        'owner_param': params[0][0] if len(params) > 0 else None,
        'operator_param': params[0][0] if len(params) > 1 else None,
        'approved_param': params[1][0] if len(params) > 2 else None
        
    }


def verify_erc3643_batchTransfer_requirements(target_func: Dict, internal_functions: List[Dict]) -> Dict:

    erc3643_requirements = {
        # 'erc3643_sender_check': False,
        'erc3643_zero_address_check_from': False,
        'erc3643_zero_address_check_to': False,
        'erc3643_frozen_wallet_check': False,
        'erc3643_balance_check': False,
        'erc3643_identity_registry_check': False,
        'erc3643_compliance_check': False,
        # 'erc3643_length_matching_check': False,
        'erc3643_event_emission_check': False
    }

    params = extract_batch_parameters(target_func)
    erc3643_from_param = 'msg.sender'
    erc3643_to_param = 'to'
    erc3643_amounts_param = 'amount'

    all_code = [(target_func['body'], "main function")]
    for func in internal_functions:
        all_code.append((func['body'], f"internal function {func['name']}"))

    for code, source in all_code:
        # # 1. Length matching check
        # if not erc3643_requirements['erc3643_length_matching_check']:
        #     length_pattern = rf'{erc3643_to_param}\.length\s*==\s*{erc3643_amounts_param}\.length'
        #     if re.search(length_pattern, code):
        #         erc3643_requirements['erc3643_length_matching_check'] = True

        # 2. Zero address checks (for _from, which is msg.sender, and _to inside loop)
        if not erc3643_requirements['erc3643_zero_address_check_from']:
            zero_from_patterns = [
                rf'{erc3643_from_param}\s*!=\s*address\(0\)',
                rf'{erc3643_from_param}\s*!=\s*0x0',
                rf'from\s*!=\s*address\(0\)',
                rf'from\s*!=\s*0x0'
            ]
            if any(re.search(p, code) for p in zero_from_patterns):
                erc3643_requirements['erc3643_zero_address_check_from'] = True

        if not erc3643_requirements['erc3643_zero_address_check_to']:
            zero_to_patterns = [
                rf'{erc3643_to_param}\[i\]\s*!=\s*address\(0\)',
                rf'{erc3643_to_param}\[i\]\s*!=\s*0x0',
                 rf'to\s*!=\s*address\(0\)',
                rf'to\s*!=\s*0x0'
            ]
            if any(re.search(p, code) for p in zero_to_patterns):
                erc3643_requirements['erc3643_zero_address_check_to'] = True

        # 3. Frozen wallet checks
        if not erc3643_requirements['erc3643_frozen_wallet_check']:
            frozen_pattern = r'!frozen\[\s*(msg\.sender|_from|_to)\s*\]'
            if re.search(frozen_pattern, code):
                erc3643_requirements['erc3643_frozen_wallet_check'] = True

        # 4. Balance check
        if not erc3643_requirements['erc3643_balance_check']:
            balance_pattern = rf'_balances\[\s*{erc3643_from_param}\s*\]\s*>=\s*{erc3643_amounts_param}'
            if re.search(balance_pattern, code):
                erc3643_requirements['erc3643_balance_check'] = True

        # 5. Identity registry check (isVerified)
        if not erc3643_requirements['erc3643_identity_registry_check']:
            id_registry_pattern = rf'tokenIdentityRegistry\.isVerified\(\s*{erc3643_to_param}\s*\)'
            if re.search(id_registry_pattern, code):
                erc3643_requirements['erc3643_identity_registry_check'] = True

        # 6. Compliance check (canTransfer)
        if not erc3643_requirements['erc3643_compliance_check']:
            compliance_pattern = rf'tokenCompliance\.canTransfer\(\s*{erc3643_from_param}\s*,\s*{erc3643_to_param}\s*,\s*{erc3643_amounts_param}\s*\)'
            if re.search(compliance_pattern, code):
                erc3643_requirements['erc3643_compliance_check'] = True

        # 7. Event emission check
        if not erc3643_requirements['erc3643_event_emission_check']:
            if re.search(r'emit\s+Transfer\(', code):
                erc3643_requirements['erc3643_event_emission_check'] = True

        # # 8. Sender check (normally implicit, but we still verify)
        # if not erc3643_requirements['erc3643_sender_check']:
        #     if erc3643_from_param in code:
        #         erc3643_requirements['erc3643_sender_check'] = True

    return erc3643_requirements


def verify_erc3643_batchForcedTransfer_requirements(target_func: Dict, internal_functions: List[Dict]) -> Dict:

    erc3643_forced_requirements = {
        'length_matching_check': False,
        'zero_address_check_from': False,
        'zero_address_check_to': False,
        'frozen_tokens_unfreeze_check': False,
        'frozen_tokens_balance_check': False,
        'identity_registry_check': False,
        'compliance_check': False,
        'unfreeze_event_check': False,
        'transfer_event_check': False
    }

    # Assume function parameters as per forced transfer
    from_list_param = 'from'
    to_list_param = 'to'
    amounts_param = 'amount'

    all_code = [(target_func['body'], "main function")]
    for func in internal_functions:
        all_code.append((func['body'], f"internal function {func['name']}"))

    for code, source in all_code:
        # 1. Length matching check
        if not erc3643_forced_requirements['length_matching_check']:
            length_pattern = rf'{from_list_param}\.length\s*==\s*{to_list_param}\.length\s*&&\s*{to_list_param}\.length\s*==\s*{amounts_param}\.length'
            length_pattern_simple = rf'{from_list_param}\.length\s*==\s*{to_list_param}\.length'
            if re.search(length_pattern, code) or re.search(length_pattern_simple, code):
                erc3643_forced_requirements['length_matching_check'] = True

        # 2. Zero address check for _from
        if not erc3643_forced_requirements['zero_address_check_from']:
            zero_from_patterns = [
                rf'{from_list_param}\[i\]\s*!=\s*address\(0\)',
                rf'{from_list_param}\[i\]\s*!=\s*0x0'
            ]
            if any(re.search(p, code) for p in zero_from_patterns):
                erc3643_forced_requirements['zero_address_check_from'] = True

        # 3. Zero address check for _to
        if not erc3643_forced_requirements['zero_address_check_to']:
            zero_to_patterns = [
                rf'{to_list_param}\[i\]\s*!=\s*address\(0\)',
                rf'{to_list_param}\[i\]\s*!=\s*0x0'
            ]
            if any(re.search(p, code) for p in zero_to_patterns):
                erc3643_forced_requirements['zero_address_check_to'] = True

        # 4. Frozen token unfreeze logic (freeBalance / frozenTokens[_from])
        if not erc3643_forced_requirements['frozen_tokens_unfreeze_check']:
            unfreeze_patterns = [
                r'if\s*\(\s*_amount\s*>\s*freeBalance\s*\)',
                r'frozenTokens\[\s*_from\s*\]\s*=\s*frozenTokens\[\s*_from\s*\]\s*-\s*tokensToUnfreeze'
            ]
            if all(re.search(p, code) for p in unfreeze_patterns):
                erc3643_forced_requirements['frozen_tokens_unfreeze_check'] = True

        # 5. Check that frozenTokens[_from] >= tokensToUnfreeze before subtract
        if not erc3643_forced_requirements['frozen_tokens_balance_check']:
            balance_pattern = r'frozenTokens\[\s*_from\s*\]\s*>=\s*tokensToUnfreeze'
            if re.search(balance_pattern, code):
                erc3643_forced_requirements['frozen_tokens_balance_check'] = True

        # 6. IdentityRegistry check
        if not erc3643_forced_requirements['identity_registry_check']:
            id_registry_pattern = rf'tokenIdentityRegistry\.isVerified\(\s*_to\s*\)'
            if re.search(id_registry_pattern, code):
                erc3643_forced_requirements['identity_registry_check'] = True

        # 7. Compliance hook check
        if not erc3643_forced_requirements['compliance_check']:
            compliance_pattern = rf'tokenCompliance\.transferred\(\s*_from\s*,\s*_to\s*,\s*_amount\s*\)'
            if re.search(compliance_pattern, code):
                erc3643_forced_requirements['compliance_check'] = True

        # 8. Unfreeze event emitted
        if not erc3643_forced_requirements['unfreeze_event_check']:
            if re.search(r'emit\s+TokensUnfrozen\(', code):
                erc3643_forced_requirements['unfreeze_event_check'] = True

        # 9. Transfer event emitted
        if not erc3643_forced_requirements['transfer_event_check']:
            if re.search(r'emit\s+Transfer\(', code):
                erc3643_forced_requirements['transfer_event_check'] = True

    return erc3643_forced_requirements


def verify_erc3643_batchBurn_requirements(target_func: Dict, internal_functions: List[Dict]) -> Dict:

    burn_requirements = {
        'length_matching_check': False,
        'zero_address_check': False,
        'balance_check': False,
        'frozen_unfreeze_check': False,
        'frozen_balance_check': False,
        'unfreeze_event_check': False,
        'burn_event_check': False,
        'compliance_destroyed_check': False
    }

    user_addresses_param = '_userAddresses'
    amounts_param = '_amounts'

    all_code = [(target_func['body'], "main function")]
    for func in internal_functions:
        all_code.append((func['body'], f"internal function {func['name']}"))

    for code, source in all_code:
        # 1. Length matching check
        if not burn_requirements['length_matching_check']:
            length_pattern = rf'{user_addresses_param}\.length\s*==\s*{amounts_param}\.length'
            if re.search(length_pattern, code):
                burn_requirements['length_matching_check'] = True

        # 2. Zero address check
        if not burn_requirements['zero_address_check']:
            zero_addr_pattern = r'_userAddress\s*!=\s*address\(0\)'
            if re.search(zero_addr_pattern, code):
                burn_requirements['zero_address_check'] = True

        # 3. Balance check
        if not burn_requirements['balance_check']:
            balance_pattern = r'_balances\[\s*_userAddress\s*\]\s*>=\s*_amount'
            if re.search(balance_pattern, code):
                burn_requirements['balance_check'] = True

        # 4. Unfreeze check if insufficient free balance
        if not burn_requirements['frozen_unfreeze_check']:
            unfreeze_pattern = r'if\s*\(\s*_amount\s*>\s*freeBalance\s*\)'
            if re.search(unfreeze_pattern, code):
                burn_requirements['frozen_unfreeze_check'] = True

        # 5. Frozen token sufficient before unfreeze
        if not burn_requirements['frozen_balance_check']:
            frozen_balance_pattern = r'frozenTokens\[\s*_userAddress\s*\]\s*>=\s*tokensToUnfreeze'
            if re.search(frozen_balance_pattern, code):
                burn_requirements['frozen_balance_check'] = True

        # 6. Emit TokensUnfrozen()
        if not burn_requirements['unfreeze_event_check']:
            if re.search(r'emit\s+TokensUnfrozen\(', code):
                burn_requirements['unfreeze_event_check'] = True

        # 7. Emit burn Transfer event
        if not burn_requirements['burn_event_check']:
            if re.search(r'emit\s+Transfer\(\s*_userAddress\s*,\s*address\(0\)\s*,', code):
                burn_requirements['burn_event_check'] = True

        # 8. Compliance destroyed hook
        if not burn_requirements['compliance_destroyed_check']:
            if re.search(r'tokenCompliance\.destroyed\(\s*_userAddress\s*,\s*_amount\s*\)', code):
                burn_requirements['compliance_destroyed_check'] = True

    return burn_requirements


def verify_erc3643_batchMint_requirements(target_func: Dict, internal_functions: List[Dict]) -> Dict:

    mint_requirements = {
        'length_matching_check': False,
        'zero_address_check': False,
        'identity_registry_check': False,
        'compliance_check': False,
        'mint_event_check': False,
        'compliance_created_check': False
    }

    to_list_param = '_toList'
    amounts_param = '_amounts'

    all_code = [(target_func['body'], "main function")]
    for func in internal_functions:
        all_code.append((func['body'], f"internal function {func['name']}"))

    for code, source in all_code:
        # 1. Length matching check
        if not mint_requirements['length_matching_check']:
            length_pattern = rf'{to_list_param}\.length\s*==\s*{amounts_param}\.length'
            if re.search(length_pattern, code):
                mint_requirements['length_matching_check'] = True

        # 2. Zero address check in _mint()
        if not mint_requirements['zero_address_check']:
            zero_addr_pattern = r'_userAddress\s*!=\s*address\(0\)'
            if re.search(zero_addr_pattern, code):
                mint_requirements['zero_address_check'] = True

        # 3. Identity Registry check
        if not mint_requirements['identity_registry_check']:
            id_registry_pattern = r'tokenIdentityRegistry\.isVerified\(\s*_to\s*\)'
            if re.search(id_registry_pattern, code):
                mint_requirements['identity_registry_check'] = True

        # 4. Compliance check
        if not mint_requirements['compliance_check']:
            compliance_pattern = r'tokenCompliance\.canTransfer\(\s*msg\.sender\s*,\s*_to\s*,\s*_amount\s*\)'
            if re.search(compliance_pattern, code):
                mint_requirements['compliance_check'] = True

        # 5. Mint Transfer event
        if not mint_requirements['mint_event_check']:
            if re.search(r'emit\s+Transfer\(\s*address\(0\)\s*,\s*_userAddress\s*,', code):
                mint_requirements['mint_event_check'] = True

        # 6. Compliance created hook
        if not mint_requirements['compliance_created_check']:
            if re.search(r'tokenCompliance\.created\(\s*_to\s*,\s*_amount\s*\)', code):
                mint_requirements['compliance_created_check'] = True

    return mint_requirements


def verify_setApprovalForAll_requirements(target_func: Dict, internal_functions: List[Dict]) -> Dict:
    """Verify if the function meets setApprovalForAll requirements."""
    requirements = {
        'self_approval_check': False,
        'status_change_check': False,
        'event_emission': False
    }
    
    params = extract_setApprovalForAll_parameters(target_func)
    operator_param = params.get('operator_param', 'operator')
    
    # operator_param = ''
    # owner_param = ''
    
    
    # Combine all code to analyze (main function + internal calls)
    all_code = [(target_func['body'], "main function")]
    for func in internal_functions:
        all_code.append((func['body'], f"internal function {func['name']}"))
        # if func['body'] and "setApprovalForAll" in func['name']:
        #     # Split parameters into a list and clean them
        #     param_list = [p.strip() for p in func['params'].split(',')]

        #     # Extract individual parameters (just the variable names)
        #     owner_param = param_list[0].split()[-1]  # Gets '_account' from 'address _account'
        #     operator_param = param_list[1].split()[-1]  # Gets '_operator' from 'address _operator'
        #     approved_param = param_list[2].split()[-1]  # Gets '_approved' from 'bool _approved'

        #     print(f"Owner parameter: {owner_param}")
        #     print(f"Operator parameter: {operator_param}")
        #     print(f"Approved parameter: {approved_param}")
            
    
    all_conditions = []
    event_pos = None
    
    for code, source in all_code:
        condition_matches = []
        # Pattern for require statements
        require_pattern = r'require\s*\(((?:[^()]|\((?:[^()]|\([^()]*\))*\))*)\)'
        # Find all require matches
        require_matches = re.finditer(require_pattern, code, re.DOTALL)
        
        for match in require_matches:
            req_content = re.sub(r'\s+', ' ', match.group(1).strip())
            condition_matches.append((req_content, source, 'require'))
        
        # Find if-revert conditions
        if_revert_conditions = find_if_revert_control_flow(code)
        for condition in if_revert_conditions:
            condition_matches.append((condition, source, 'if-revert'))
            
        all_conditions.extend(condition_matches)
    
    # Possible sender representations
    sender_reprs = ['msg.sender', '_msgSender()', 'sender', 'owner', "owner_", '_account', 'account']
    
    # Check conditions
    for condition_content, condition_source, condition_type in all_conditions:
        # Check for self-approval prevention
        if not requirements['self_approval_check']:
            for sender in sender_reprs:
                escaped_operator = re.escape(operator_param)
                # print(f"sender :{sender}")
                # print(f"operator_param :{operator_param}")
                
                # patterns = [
                #     rf'{owner_param}\s*==\s*{operator_param}',
                #     rf'{operator_param}\s*==\s*{owner_param}',
                #     rf'{owner_param}\s*!=\s*{operator_param}',
                #     rf'{operator_param}\s*!=\s*{owner_param}'
                # ]
                patterns1 = [
                    rf'{sender}\s*==\s*{operator_param}',
                    rf'{operator_param}\s*==\s*{sender}',
                    rf'{sender}\s*!=\s*{operator_param}',
                    rf'{operator_param}\s*!=\s*{sender}'
                ]
                
                patterns2 = [
                    rf'{re.escape(sender)}\s*\(\s*\)\s*!=\s*{escaped_operator}',  # _msgSender() != operator
                    rf'{escaped_operator}\s*!=\s*{re.escape(sender)}\s*\(\s*\)',  # operator != _msgSender()
                    rf'{re.escape(sender)}\s*!=\s*{escaped_operator}',            # msg.sender != operator (fallback)
                    rf'{escaped_operator}\s*!=\s*{re.escape(sender)}'             # operator != msg.sender (fallback)
                ]
                if any(re.search(p, condition_content) for p in patterns1) or \
                    (any(re.search(p, condition_content) for p in patterns2)):
                    requirements['self_approval_check'] = True
                    break
        
        # # Check for zero address operator
        # if not requirements['zero_address_check']:
        #     zero_addr_patterns = [
        #         rf'{operator_param}\s*==\s*address\(0\)',
        #         rf'address\(0\)\s*==\s*{operator_param}',
        #         rf'{operator_param}\s*!=\s*address\(0\)',
        #         rf'address\(0\)\s*!=\s*{operator_param}'
        #     ]
        #     if any(re.search(p, condition_content) for p in zero_addr_patterns):
        #         requirements['zero_address_check'] = True
        
        # Check for status change validation (front-running protection)
        # if not requirements['frontrunning_protection']:
        #     status_patterns = [
        #         rf'_operatorApprovals\[{sender}\]\[{operator_param}\]\s*==\s*approved',
        #         rf'operatorApprovals\[{sender}\]\[{operator_param}\]\s*==\s*approved',
        #         rf'_approvals\[{sender}\]\[{operator_param}\]\s*==\s*approved',
        #         rf'approvals\[{sender}\]\[{operator_param}\]\s*==\s*approved'
        #     ]
        #     if any(re.search(p, condition_content) for p in status_patterns):
        #         requirements['frontrunning_protection'] = True
    
    # Check for event emission in the code
    for code, source in all_code:
        # Event emission check
        if 'emit ApprovalForAll(' in code:
            requirements['event_emission'] = True
            event_pos = (source, code.find('emit ApprovalForAll('))
            
            # Verify event is emitted after all checks
            if event_pos:
                pre_event_code = code[:event_pos[1]]
                check_patterns = [
                    r'require\s*\(',
                    r'if\s*\(',
                    r'revert\s*\('
                ]
                if any(re.search(p, pre_event_code) for p in check_patterns):
                    requirements['status_change_check'] = True
    
    return requirements


def verify_erc2612_requirements(target_func: Dict, internal_functions: List[Dict]) -> Dict:
    """Verify if the function and its internal calls meet ERC2612 requirements."""
    requirements = {
        'deadline_check': False,
        'timestamp_check': False,
        'signature_validation': False,
        'nonce_usage': False,
        'domain_separator_usage': False,
        'permit_function_exists': False,
        'owner_check': False,
        'spender_approval': False
    }

    # Extract parameters
    params = extract_parameters(target_func)
    owner_param = params.get('owner_param', 'owner')
    spender_param = params.get('spender_param', 'spender')
    value_param = params.get('value_param', 'value')
    deadline_param = params.get('deadline_param', 'deadline')
    v_param = params.get('v_param', 'v')
    r_param = params.get('r_param', 'r')
    s_param = params.get('s_param', 's')

    # Combine all code to analyze (main function + internal calls)
    all_code = [(target_func['body'], "main function")]
    for func in internal_functions:
        if target_func['body'] != func['body']:
            all_code.append((func['body'], f"internal function {func['name']}"))

    all_conditions = []
    
    for code, source in all_code:
        condition_matches = []
        
        # Pattern for require statements
        require_pattern = r'require\s*\(((?:[^()]|\((?:[^()]|\([^()]*\))*\))*)\)'
        require_matches = re.finditer(require_pattern, code, re.DOTALL)
        
        for match in require_matches:
            req_content = re.sub(r'\s+', ' ', match.group(1).strip())
            condition_matches.append((req_content, source, 'require'))
        
        # Find if-revert conditions
        if_revert_conditions = find_if_revert_control_flow(code)
        for condition in if_revert_conditions:
            condition_matches.append((condition, source, 'if-revert'))
            
        all_conditions.extend(condition_matches)

    # Check conditions
    for condition_content, condition_source, condition_type in all_conditions:
        # Check for deadline validation
        if deadline_param and not requirements['deadline_check']:
            if condition_type == "if-revert":
                deadline_patterns = [
                    rf'{deadline_param}\s*<\s*block\.timestamp',
                    rf'block\.timestamp\s*>\s*{deadline_param}',
                    rf'isExpired\(\s*{deadline_param}\s*\)',
                    rf'!isValid\(\s*{deadline_param}\s*\)'
                ]
            else:  # require
                deadline_patterns = [
                    rf'{deadline_param}\s*>=\s*block\.timestamp',
                    rf'block\.timestamp\s*<=\s*{deadline_param}',
                    rf'!isExpired\(\s*{deadline_param}\s*\)',
                    rf'isValid\(\s*{deadline_param}\s*\)'
                ]
            
            if any(re.search(p, condition_content) for p in deadline_patterns):
                requirements['deadline_check'] = True

        # Check for timestamp validation (separate from deadline)
        if not requirements['timestamp_check']:
            timestamp_patterns = [
                r'block\.timestamp',
                r'now\s*[<>=]',
                r'timestamp\s*[<>=]'
            ]
            if any(re.search(p, condition_content) for p in timestamp_patterns):
                requirements['timestamp_check'] = True

        # Check for signature validation
        if (v_param and r_param and s_param) and not requirements['signature_validation']:
            sig_patterns = [
                r'ecrecover\s*\(',
                r'ECDSA\.recover\s*\(',
                r'signature\s*=\s*abi\.encodePacked\s*\(',
                r'\.verify\s*\('
            ]
            if any(re.search(p, condition_content) for p in sig_patterns):
                requirements['signature_validation'] = True

        # Check for nonce usage
        if not requirements['nonce_usage']:
            if re.search(r'nonces\[', condition_content) or re.search(r'incrementNonce\s*\(', condition_content):
                requirements['nonce_usage'] = True

    # Additional checks that don't depend on conditions
    for code, source in all_code:
        # Check for DOMAIN_SEPARATOR usage
        if not requirements['domain_separator_usage']:
            if re.search(r'DOMAIN_SEPARATOR', code) or re.search(r'domainSeparator\s*\(', code):
                requirements['domain_separator_usage'] = True

        # Check for permit function existence
        if not requirements['permit_function_exists']:
            if re.search(r'function\s+permit\s*\(', code):
                requirements['permit_function_exists'] = True

        # Check for owner validation
        if owner_param and not requirements['owner_check']:
            owner_patterns = [
                rf'{owner_param}\s*==\s*msg\.sender',
                rf'msg\.sender\s*==\s*{owner_param}',
                rf'isOwner\(\s*{owner_param}\s*\)',
                rf'ownerOf\(\s*{owner_param}\s*\)'
            ]
            if any(re.search(p, code) for p in owner_patterns):
                requirements['owner_check'] = True

        # Check for spender approval
        if spender_param and not requirements['spender_approval']:
            if re.search(rf'approve\(\s*{spender_param}\s*,', code):
                requirements['spender_approval'] = True

    return requirements


def verify_erc5267_requirements(target_func: Dict, internal_functions: List[Dict]) -> Dict:
    """
    Verify ERC-5267 eip712Domain() implementation.

    Correct interpretation:
      - ERC-5267 requires the function signature and return tuple shape.
      - The `fields` bitmap determines which EIP-712 fields are present.
      - name/version/chainId/verifyingContract/salt are not all mandatory.
      - salt = bytes32(0) is NOT a bug if the salt bit is absent.
      - version = "" is NOT a bug if the version bit is absent.
      - The real bug is mismatch between ERC-5267 metadata and the actual
        EIP-712 domain used for verification, or semantic insufficiency
        such as missing verifyingContract or chainId in risky contexts.

    Args:
        target_func: Dict for eip712Domain function.
        internal_functions: related internal functions discovered by your analysis.

    Returns:
        Dict with compliance, decoded bitmap, warnings, and critical issues.
    """

    import re

    def strip_comments(code: str) -> str:
        """Remove Solidity comments for easier regex matching."""
        code = re.sub(r"/\*.*?\*/", "", code, flags=re.DOTALL)
        code = re.sub(r"//.*", "", code)
        return code

    def decode_erc5267_fields(fields_value: int) -> Dict[str, bool]:
        """
        ERC-5267 bitmap:
          bit 0: name
          bit 1: version
          bit 2: chainId
          bit 3: verifyingContract
          bit 4: salt
        """
        return {
            "name": bool(fields_value & 0x01),
            "version": bool(fields_value & 0x02),
            "chainId": bool(fields_value & 0x04),
            "verifyingContract": bool(fields_value & 0x08),
            "salt": bool(fields_value & 0x10),
        }

    def normalize_expr(expr: str) -> str:
        return re.sub(r"\s+", "", expr or "")

    def extract_return_tuple(code: str):
        """
        Extract the top-level return tuple from:
            return (...);
        This is more robust than one giant regex because return values can contain
        nested calls such as _EIP712Name(), bytes32(0), new uint256[](0), etc.
        """
        m = re.search(r"\breturn\s*\(", code)
        if not m:
            return None

        start = m.end()  # position after "return("
        depth = 1
        i = start
        while i < len(code):
            ch = code[i]
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    tuple_text = code[start:i]
                    return split_top_level_commas(tuple_text)
            i += 1

        return None

    def split_top_level_commas(s: str):
        """
        Split 'a, f(x,y), new uint256[](0)' into top-level arguments.
        """
        parts = []
        cur = []
        paren = bracket = brace = 0
        in_str = False
        quote = ""

        i = 0
        while i < len(s):
            ch = s[i]

            if in_str:
                cur.append(ch)
                if ch == quote and (i == 0 or s[i - 1] != "\\"):
                    in_str = False
                i += 1
                continue

            if ch in ("'", '"'):
                in_str = True
                quote = ch
                cur.append(ch)
            elif ch == "(":
                paren += 1
                cur.append(ch)
            elif ch == ")":
                paren -= 1
                cur.append(ch)
            elif ch == "[":
                bracket += 1
                cur.append(ch)
            elif ch == "]":
                bracket -= 1
                cur.append(ch)
            elif ch == "{":
                brace += 1
                cur.append(ch)
            elif ch == "}":
                brace -= 1
                cur.append(ch)
            elif ch == "," and paren == 0 and bracket == 0 and brace == 0:
                parts.append("".join(cur).strip())
                cur = []
            else:
                cur.append(ch)

            i += 1

        if cur:
            parts.append("".join(cur).strip())

        return parts

    def parse_fields_value(fields_expr: str):
        """
        Parse fields expression:
          hex"0f"
          0x0f
          bytes1(0x0f)
          bytes1(uint8(0x0f))
        Returns int or None.
        """
        expr = fields_expr.strip()

        patterns = [
            r'hex"([0-9a-fA-F]{1,2})"',
            r"0x([0-9a-fA-F]{1,2})",
            r"bytes1\s*\(\s*0x([0-9a-fA-F]{1,2})\s*\)",
            r"uint8\s*\(\s*0x([0-9a-fA-F]{1,2})\s*\)",
        ]

        for pat in patterns:
            m = re.search(pat, expr)
            if m:
                return int(m.group(1), 16)

        # decimal literal, e.g., 15 or bytes1(uint8(15))
        m = re.search(r"\b([0-9]{1,3})\b", expr)
        if m:
            val = int(m.group(1))
            if 0 <= val <= 255:
                return val

        return None

    def expr_looks_dynamic_chainid(expr: str) -> bool:
        e = normalize_expr(expr).lower()
        return "block.chainid" in e or "chainid()" in e

    def expr_looks_address_this(expr: str) -> bool:
        e = normalize_expr(expr).lower()
        return "address(this)" in e

    def expr_looks_zero_salt(expr: str) -> bool:
        e = normalize_expr(expr).lower()
        return (
            e in {"0", "bytes32(0)", "bytes32(0x0)", "bytes32(uint256(0))"}
            or re.fullmatch(r"0x0+", e or "") is not None
        )

    def expr_looks_empty_extensions(expr: str) -> bool:
        e = normalize_expr(expr).lower()
        return (
            "newuint256[](0)" in e
            or e == "[]"
            or e == "extensions"
        )

    def has_domain_separator_typehash(code: str) -> bool:
        return bool(
            re.search(r"EIP712Domain\s*\(", code)
            or re.search(r"8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f", code, re.I)
        )

    def has_domain_separator_usage(code: str) -> bool:
        return bool(
            re.search(r"\bDOMAIN_SEPARATOR\b", code)
            or re.search(r"_domainSeparatorV4\s*\(", code)
            or re.search(r"_hashTypedDataV4\s*\(", code)
            or re.search(r"\x19\x01|0x1901|1901", code)
        )

    requirements = {
        "eip712Domain_function_exists": False,
        "returns_correct_tuple_shape": False,
        "returns_correct_fields": False,

        "typehash_declared_or_used": False,
        "domain_separator_usage": False,

        "fields": {
            "valid": False,
            "raw": None,
            "value": None,
            "decoded": {
                "name": False,
                "version": False,
                "chainId": False,
                "verifyingContract": False,
                "salt": False,
            },
            "unknown_bits": False,
        },

        "name": {
            "present_by_bitmap": False,
            "return_expr": None,
            "valid_if_present": False,
        },
        "version": {
            "present_by_bitmap": False,
            "return_expr": None,
            "valid_if_present": False,
        },
        "chainId": {
            "present_by_bitmap": False,
            "return_expr": None,
            "valid_if_present": False,
            "uses_block_chainid_or_chainid_opcode": False,
            "possibly_hardcoded": False,
        },
        "verifyingContract": {
            "present_by_bitmap": False,
            "return_expr": None,
            "valid_if_present": False,
            "uses_address_this": False,
            "possibly_hardcoded": False,
        },
        "salt": {
            "present_by_bitmap": False,
            "return_expr": None,
            "valid_if_present": False,
            "zero_placeholder_when_absent": False,
            "non_zero_when_present": False,
        },
        "extensions": {
            "return_expr": None,
            "valid": False,
            "empty": False,
            "non_empty": False,
        },

        "erc5267_classification": None,

        "warnings": [],
        "critical_issues": [],
        "notes": [],
    }

    # Combine visible code.
    all_code_parts = [target_func.get("body", "")]
    for func in internal_functions or []:
        body = func.get("body", "")
        if body and body not in all_code_parts:
            all_code_parts.append(body)

    combined_code = "\n\n".join(all_code_parts)
    code_no_comments = strip_comments(combined_code)

    # ERC-5267 signature check.
    # We do not require exact spacing or memory keywords.
    eip712_domain_sig = re.compile(
        r"function\s+eip712Domain\s*\(\s*\)\s*"
        r"(?:external|public)\s+view\s+"
        r"(?:virtual\s+)?(?:override\s+)?"
        r"returns\s*\(",
        re.DOTALL,
    )

    if eip712_domain_sig.search(code_no_comments):
        requirements["eip712Domain_function_exists"] = True
    else:
        # The parser may pass only the function body without the signature.
        # If target signature was already matched by caller, allow body-only analysis.
        if target_func.get("name") == "eip712Domain" or target_func.get("signature") == "eip712Domain()":
            requirements["eip712Domain_function_exists"] = True
            requirements["notes"].append("Function signature not visible in body; assuming caller matched eip712Domain().")
        else:
            requirements["critical_issues"].append("eip712Domain() function signature not detected.")

    # Extract return tuple.
    return_values = extract_return_tuple(code_no_comments)
    if not return_values:
        requirements["critical_issues"].append("No return tuple found in eip712Domain().")
    elif len(return_values) != 7:
        requirements["critical_issues"].append(
            f"eip712Domain() should return 7 values, found {len(return_values)}."
        )
    else:
        requirements["returns_correct_tuple_shape"] = True

        fields_expr, name_expr, version_expr, chain_expr, verifier_expr, salt_expr, extensions_expr = return_values

        requirements["fields"]["raw"] = fields_expr
        requirements["name"]["return_expr"] = name_expr
        requirements["version"]["return_expr"] = version_expr
        requirements["chainId"]["return_expr"] = chain_expr
        requirements["verifyingContract"]["return_expr"] = verifier_expr
        requirements["salt"]["return_expr"] = salt_expr
        requirements["extensions"]["return_expr"] = extensions_expr

        fields_value = parse_fields_value(fields_expr)
        requirements["fields"]["value"] = fields_value

        if fields_value is None:
            requirements["warnings"].append(
                f"Could not statically parse ERC-5267 fields bitmap expression: {fields_expr}"
            )
        elif fields_value == 0:
            requirements["critical_issues"].append("ERC-5267 fields bitmap is zero; no EIP-712 domain fields reported.")
        else:
            decoded = decode_erc5267_fields(fields_value)
            requirements["fields"]["decoded"] = decoded
            requirements["fields"]["valid"] = True

            if fields_value & ~0x1F:
                requirements["fields"]["unknown_bits"] = True
                requirements["warnings"].append(
                    f"ERC-5267 fields bitmap has bits outside EIP-712 base fields: 0x{fields_value:x}"
                )

            # Presence flags.
            requirements["name"]["present_by_bitmap"] = decoded["name"]
            requirements["version"]["present_by_bitmap"] = decoded["version"]
            requirements["chainId"]["present_by_bitmap"] = decoded["chainId"]
            requirements["verifyingContract"]["present_by_bitmap"] = decoded["verifyingContract"]
            requirements["salt"]["present_by_bitmap"] = decoded["salt"]

            # name validation.
            if decoded["name"]:
                if name_expr and name_expr.strip():
                    requirements["name"]["valid_if_present"] = True
                else:
                    requirements["critical_issues"].append("name bit is set but returned name expression is empty.")
            else:
                if name_expr.strip() not in {"", '""'}:
                    requirements["notes"].append("name bit is absent; returned name value is unspecified and ignored.")

            # version validation.
            if decoded["version"]:
                if version_expr and version_expr.strip() and version_expr.strip() != '""':
                    requirements["version"]["valid_if_present"] = True
                else:
                    requirements["warnings"].append("version bit is set but version appears empty.")
            else:
                if version_expr.strip() not in {"", '""'}:
                    requirements["notes"].append("version bit is absent; returned version value is unspecified and ignored.")

            # chainId validation.
            if decoded["chainId"]:
                if expr_looks_dynamic_chainid(chain_expr):
                    requirements["chainId"]["uses_block_chainid_or_chainid_opcode"] = True
                    requirements["chainId"]["valid_if_present"] = True
                else:
                    requirements["chainId"]["possibly_hardcoded"] = True
                    requirements["warnings"].append(
                        f"chainId bit is set but chainId does not obviously use block.chainid/chainid(): {chain_expr}"
                    )
            else:
                requirements["warnings"].append(
                    "Domain omits chainId; check for cross-chain replay risk if signatures can cross chains."
                )

            # verifyingContract validation.
            if decoded["verifyingContract"]:
                if expr_looks_address_this(verifier_expr):
                    requirements["verifyingContract"]["uses_address_this"] = True
                    requirements["verifyingContract"]["valid_if_present"] = True
                else:
                    requirements["verifyingContract"]["possibly_hardcoded"] = True
                    requirements["warnings"].append(
                        f"verifyingContract bit is set but verifier is not obviously address(this): {verifier_expr}"
                    )
            else:
                requirements["critical_issues"].append(
                    "Domain omits verifyingContract; possible cross-contract replay risk."
                )

            # salt validation.
            if decoded["salt"]:
                if salt_expr and salt_expr.strip():
                    requirements["salt"]["valid_if_present"] = True
                    if not expr_looks_zero_salt(salt_expr):
                        requirements["salt"]["non_zero_when_present"] = True
                    else:
                        requirements["warnings"].append(
                            "salt bit is set but salt appears to be zero; check whether this is intentional."
                        )
                else:
                    requirements["critical_issues"].append("salt bit is set but returned salt expression is empty.")
            else:
                # bytes32(0) is correct placeholder when salt is absent.
                if expr_looks_zero_salt(salt_expr):
                    requirements["salt"]["zero_placeholder_when_absent"] = True
                    requirements["notes"].append("salt bit is absent; zero salt return value is ignored by ERC-5267.")
                else:
                    requirements["notes"].append("salt bit is absent; returned salt value is unspecified and ignored.")

            # extensions validation.
            if extensions_expr and extensions_expr.strip():
                requirements["extensions"]["valid"] = True
                if expr_looks_empty_extensions(extensions_expr):
                    requirements["extensions"]["empty"] = True
                else:
                    requirements["extensions"]["non_empty"] = True
                    requirements["warnings"].append(
                        f"Non-empty or dynamic ERC-5267 extensions returned: {extensions_expr}. Verify referenced EIPs."
                    )
            else:
                requirements["critical_issues"].append("extensions return expression missing.")

            # Classification.
            if fields_value == 0x0D:
                requirements["erc5267_classification"] = "name_chainId_verifyingContract"
            elif fields_value == 0x0F:
                requirements["erc5267_classification"] = "name_version_chainId_verifyingContract"
            elif fields_value == 0x1F:
                requirements["erc5267_classification"] = "name_version_chainId_verifyingContract_salt"
            else:
                requirements["erc5267_classification"] = f"custom_bitmap_0x{fields_value:x}"

    # Supplemental checks over combined code.
    requirements["typehash_declared_or_used"] = has_domain_separator_typehash(combined_code)
    requirements["domain_separator_usage"] = has_domain_separator_usage(combined_code)

    # These are not ERC-5267 compliance failures by themselves, only useful notes.
    if not requirements["typehash_declared_or_used"]:
        requirements["notes"].append(
            "EIP712Domain typehash not visible in analyzed slice; may be inherited/library code or outside current analysis scope."
        )

    if not requirements["domain_separator_usage"]:
        requirements["notes"].append(
            "DOMAIN_SEPARATOR/_domainSeparatorV4 usage not visible in analyzed slice; compare ERC-5267 output with actual verifier domain separately."
        )

    # Final high-level correctness.
    if requirements["eip712Domain_function_exists"] and requirements["returns_correct_tuple_shape"] and requirements["fields"]["valid"]:
        # Must not have structural critical issues.
        structural_criticals = [
            issue for issue in requirements["critical_issues"]
            if (
                "7 values" in issue
                or "No return tuple" in issue
                or "fields bitmap is zero" in issue
                or "function signature not detected" in issue
            )
        ]
        requirements["returns_correct_fields"] = len(structural_criticals) == 0

    return requirements


def analyze_transferFrom_interprocedural_analysis(solidity_code: str, target_sig: str = "transferFrom(address,address,uint256)") -> Dict:
    """Main analysis function for transferFrom compliance with allowance check."""
    all_functions = find_all_functions(solidity_code)
    
    
    target_funcs = find_functions_by_signature(all_functions, target_sig)
    print(f"len of target_funcs count: {len(target_funcs)}")
    
    
    if not target_funcs:
        return {"error": "transferFrom function not found"}
    
    results = []
    for target_func in target_funcs:
        # if contains_assembly(target_func['body']):
        #     print(f"assembly in target_func: {target_func['name']}")
        #     break
        
        internal_calls = get_all_internal_calls(target_func['body'], all_functions)
        # for f in internal_calls:
        #     if contains_assembly(f['body']):
        #         print(f"assembly in internal_calls: {f['name']}")
        #         break
        
        if internal_calls is None:
            print(f"internal_calls is None")
            # continue
            
        # requirements = verify_transferFrom_requirements(target_func, internal_calls)
        requirements = verify_erc5267_requirements(target_func, internal_calls)
        # print(f"requirements:{requirements}")
        
        
        # all_reqs = [
        #     # 'sender_check',
        #     'allowance_check',
        #     'conditional_allowance_check'
        #     # 'balance_check',
        #     # 'zero_address_check',
        #     # 'approval_event_found'
        # ]
        
        # all_met = all(requirements.get(req, False) for req in all_reqs)
        # some_met = any(requirements.get(req, False) for req in all_reqs)
        
        results.append({
            # "function": target_func['name'],
            # "implementation_location": f"Line {target_func['start']}-{target_func['end']}",
            # "parameters": target_func.get('parameters', {}),
            "requirements": requirements,
            # "internal_calls": [f['name'] for f in internal_calls],
            # "allowance_check_found": requirements.get('allowance_check', False),
            # "all_requirements_met": all_met,
            # "some_requirements_met": some_met
        })
    
    if results:
        return {
            "all_implementations": results,
            # "summary": {
            #     "total_implementations": len(results),
            #     "fully_compliant": sum(1 for r in results if r.get('all_requirements_met', False)),
            #     "partially_compliant": sum(1 for r in results if r.get('some_requirements_met', False))
            # }
        }
    return {"error": "No valid implementations found (possibly due to recursive calls)"}


def verify_transferFrom_requirements(target_func: Dict, internal_functions: List[Dict]) -> Dict:
    """
    Verify if transferFrom function meets ERC20 requirements:
    1. allowance check (msg.sender must have allowance)
    2. sender != zero address
    3. recipient != zero address
    4. sufficient balance
    5. Approval event emitted
    """
    requirements = {
        # 'sender_check': False,
        'allowance_check': False,
        'conditional_allowance_check': False,
        # 'balance_check': False,
        # 'zero_address_check': False,
        # 'approval_event_found': False
    }
    
    # Extract parameters
    params = extract_transferFrom_parameters(target_func)
    from_param = params.get('from_param', 'from')
    to_param = params.get('to_param', 'to')
    amount_param = params.get('amount_param', 'amount')
    
    # Combine all code for analysis
    all_code = [(target_func['body'], "main function")]
    print(f"Searching in all_code: {all_code}")
    if(internal_functions is not None):
        for func in internal_functions:
            all_code.append((func['body'], f"internal function {func['name']}"))

    sender_reprs = ['msg.sender', '_msgSender()']
    
    # Analyze all conditions
    for code, source in all_code:
        
        # Remove multi-line and single-line comments
        code = re.sub(r'/\*.*?\*/', '', code, flags=re.DOTALL)
        code = re.sub(r'//.*$', '', code, flags=re.MULTILINE)
        # Find require statements
        require_pattern = r'require\s*\(((?:[^()]|\((?:[^()]|\([^()]*\))*\))*)\)'
        require_matches = re.finditer(require_pattern, code, re.DOTALL)
        
        # for match in require_matches:
        # req_content = re.sub(r'\s+', ' ', match.group(1).strip())
        
        # Pattern for allowance check inside if condition
        
        sub_pattern3 = r'_?a?pprove\s*\([^,]+,\s*[^,]+,\s*_?_?allowances?\[[^\]]+\]\[[^\]]+\]\s*-?\s*[^,)]+\)'
        if re.search(sub_pattern3, code, re.DOTALL): 
            requirements['allowance_check'] = True
            break
        
        sub_pattern5 = r'_?a?pprove\s*\([^;]+_?_?allowances?\[[^\]]+\]\[[^\]]+\]\.sub\s*\('
        if re.search(sub_pattern5, code, re.DOTALL): 
            requirements['allowance_check'] = True
            break
        
        sub_pattern6 = r'if\s*\([^;]*_*_*allowances?\[[^\]]+\]\[[^\]]+\]\s*>=\s*[^;]*\)'
        if re.search(sub_pattern6, code, re.DOTALL): 
            requirements['allowance_check'] = True
            break
        
        sub_pattern7 = r'require\s*\([^;]*_*_*allowances?\[[^\]]+\]\[[^\]]+\]\s*>=\s*[^;]*\)'
        if re.search(sub_pattern7, code, re.DOTALL): 
            requirements['allowance_check'] = True
            break
        sub_pattern8 = r'require\s*\([^;]*_*_*allowances?\[[^\]]+\]\[[^\]]+\]\s*[<>=]+\s*[^,]+,\s*["\'][^"\']*["\']\s*\)'
        if re.search(sub_pattern8, code, re.DOTALL): 
            requirements['allowance_check'] = True
            break
        
        sub_pattern9 = r'require\s*\([^;]*_*_*allowances?\[[^\]]+\]\[[^\]]+\]\s*[<>=]+\s*[^,]+,\s*["\'][^"\']*["\']\s*\)'
        if re.search(sub_pattern9, code, re.DOTALL): 
            requirements['allowance_check'] = True
            break
        
        var_match = re.search(r'uint256\s+(\w+)\s*=\s*_?_?allowances?\[[^\]]+\]\[[^\]]+\]', code)
        if var_match:
            var_name = var_match.group(1)  # Captures "allowed"
            print(f"var_name:{var_name}")
            
            # Step 2: Check if that variable appears in an if condition
            if_var_pattern = rf'if\s*\(\s*{var_name}\s*!=\s*type\(uint256\)\.max\s*\)'
            if re.search(if_var_pattern, code):
                requirements['allowance_check'] = True
                # requirements['conditional_allowance_check'] = False
                # print(f"variable appears in an if condition")
                break
            if_var_pattern1 = rf'if\s*\(\s*{var_name}\s*!=\s*[^)]+\)'
            if re.search(if_var_pattern1, code):
                requirements['allowance_check'] = True
                # requirements['conditional_allowance_check'] = False
                # print(f"variable appears in an if condition")
                break
        
        sub_pattern10 = r'if\s*\([^{]*!=[^{]*\)\s*\{[^{}]*_*_*allowances?\[[^\]]+\]\[[^\]]+\]'
        if re.search(sub_pattern10, code, re.DOTALL): 
            requirements['allowance_check'] = True
            break
        
        # sub_pattern2 = r'if\s*\([^;]*\)\s*\{?[^;]*?_?_?allowances?\[[^\]]+\]\[[^\]]+\]'
        sub_pattern2 = r'if\s*\((?![^)]*_?_?allowances?\[)[^)]*\)\s*\{?[^;]*?_?_?allowances?\[[^\]]+\]\[[^\]]+\]'
        # sub_pattern2 = r'if\s*\((?![^)]*_?_?allowances?\[[^\]]+\]\[[^\]]+\)[^)]*\)\s*\{?[^;]*?_?_?allowances?\[[^\]]+\]\[[^\]]+\]'
        if re.search(sub_pattern2, code, re.DOTALL): 
            requirements['conditional_allowance_check'] = True
            print(f"✅ allowance_check inside the if condition block in {source}")
            break
        
       
            
            
        
        # # Debug: Print the code when '_allowances' is found
        # if '_allowances' in code:
            print(f"\n🔍 Found '_allowances' in {source}")
            print(f"   Looking for if pattern...")
            
            # Test the pattern
            match = re.search(sub_pattern2, code, re.DOTALL)
            if match:
                print(f"   ✅ PATTERN MATCHED")
                print(f"   Matched text: {match.group(0)[:200]}")
            else:
                print(f"   ❌ PATTERN DID NOT MATCH")
                
                # Check condition separately
                if_pattern = r'if\s*\([^;]*?\)'
                if_match = re.search(if_pattern, code, re.DOTALL)
                if if_match:
                    print(f"   Found if statement: {if_match.group(0)}")
                    
                    # Check if condition contains _allowances
                    condition = if_match.group(0)
                    if '_allowances' in condition:
                        print(f"   → Condition contains _allowances (should NOT match)")
                    else:
                        print(f"   → Condition does NOT contain _allowances")
                        
                        # Check if body contains _allowances after the if
                        after_if = code[if_match.end():]
                        if '_allowances' in after_if:
                            print(f"   → Body contains _allowances (SHOULD match!)")
                            print(f"   Body snippet: {after_if[:200]}")
        
        
        
        
        sub_pattern4 = r'require\s*\(\s*_*allowances?\[[^\]]+\]\[[^\]]+\]\s*>=\s*[^,]+,\s*["\'][^"\']*["\']\s*\)'
        if re.search(sub_pattern4, code, re.DOTALL): 
            requirements['allowance_check'] = True
            break
        # Debug for _allowances presence
        # if '_allowances' in code:
        #     print(f"   ✅ Found '_allowances' in {source}")
        #     # Print the actual line
        #     for line in code.split('\n'):
        #         if '_allowances' in line:
        #             print(f"      Line: {line.strip()[:150]}")
        #             break
        
        # 2. ALLOWANCE CHECK - MODIFIED FOR .sub() DETECTION
        if not requirements['allowance_check']:
            # First, check the entire code (not just require conditions) for .sub() pattern
            for check_sender in sender_reprs:
                # .sub() pattern - captures allowance subtraction regardless of require wrapper
                sub_pattern = rf'_?allowances?\[{from_param}\]\[{re.escape(check_sender)}\]\.sub\s*\(\s*{amount_param}\s*,'
                
                if re.search(sub_pattern, code, re.DOTALL):
                    requirements['allowance_check'] = True
                    break
                
                # Also check for allowance[from][msg.sender].sub pattern
                sub_pattern2 = rf'_?allowances?\[{from_param}\]\[{re.escape(check_sender)}\]\.sub\s*\(\s*{amount_param}\s*,'
                if re.search(sub_pattern2, code, re.DOTALL):
                    requirements['allowance_check'] = True
                    break
                # Pattern matches: _allowances[anything][anything].sub(anything, "error")
                sub_pattern = r'_?allowances?\[[^\]]+\]\[[^\]]+\]\.sub\s*\([^,]+,\s*["\'][^"\']*["\']\s*\)'

                # DEBUG: Print the code being searched
                # print(f"Searching in: {source}")
                # print(f"Code snippet: {code[:2000]}")  # First 500 chars
                # print(f"Looking for pattern: {sub_pattern}")
                
                if re.search(sub_pattern, code, re.DOTALL): 
                    requirements['allowance_check'] = True
                    break
                
                # Pattern matches: _allowances[anything][anything]
                sub_pattern1 = r'return\s+_?allowances?\[[^\]]+\]\[[^\]]+\]'
                if re.search(sub_pattern1, code, re.DOTALL): 
                    requirements['allowance_check'] = True
                    break
                

                if '.sub(' in code:
                    requirements['allowance_check'] = True
                    print(f"✅ Found .sub() in {source}")
                    break
            
                # Also check in require conditions
                allowance_patterns = [
                    rf'_?allowances?\[{from_param}\]\[{re.escape(s)}\]\s*>=\s*{amount_param}' for s in sender_reprs
                ] + [
                    rf'_?allowances?\[{from_param}\]\[{re.escape(s)}\]\s*>=\s*{amount_param}' for s in sender_reprs
                ] + [
                    rf'_?allowances?\(\s*{from_param}\s*,\s*{re.escape(s)}\s*\)\s*>=\s*{amount_param}' for s in sender_reprs
                ] + [
                    rf'require\s*\(\s*_?allowances?\[{from_param}\]\[{re.escape(s)}\]\.sub\s*\(\s*{amount_param}\s*,' for s in sender_reprs
                ]
                
                for pattern in allowance_patterns:
                    if re.search(pattern, code, re.DOTALL):
                        requirements['allowance_check'] = True
                        break
        
       
    
    return requirements

