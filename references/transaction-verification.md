# Transaction verification

This workflow is chain-agnostic. Terms below use Solana vocabulary (slot, signer, CPI); substitute block, from/to, and internal call for EVM chains.

Use this workflow when an agent has decoded, labeled, scored, summarized, or generated a schema or row for a blockchain transaction and the result can be checked against canonical chain data and an explorer page.

## Evidence packet

Record:

- chain, network, transaction signature/hash, slot or block, and observation time;
- the agent's exact structured claims;
- the generated schema and row values, including field definitions, types, null semantics, and provenance when data QA is in scope;
- canonical RPC or indexed transaction record when available;
- one or more explorer URLs as human-inspectable corroboration;
- decoder version, data cutoff, and any unavailable fields.

An explorer is an evidence surface, not infallible ground truth. Explorer labels may be stale, UI summaries may omit inner instructions, and decoded presentation can differ across providers. Prefer raw chain/RPC facts for mechanics and use explorer pages to independently inspect presentation, attribution, and transaction anatomy.

## Compare field by field

Map every generated field to its claimed meaning and evidence source before comparing values. Verify both schema semantics and row contents; a value in the wrong field, unit, type, sign convention, or null state is a defect even when the underlying transaction was identified correctly.

Check at least:

- signature/hash, status, block/slot, and timestamp;
- fee payer and signers;
- program or contract calls, including inner/CPI calls when relevant;
- native and token balance changes with mint, owner, decimals, and direction;
- instruction ordering and transfer roles;
- memo, failure, and error semantics;
- whether entity labels are sourced facts, explorer attributions, or agent inference;
- whether the evidence supports the final classification and the reasoning used to reach it.

For generated datasets, also check that each material value is traceable to canonical RPC or indexed facts, or is clearly marked as explorer attribution or agent inference. Inspect the explorer's listing for the same transaction as corroboration. Do not copy the explorer presentation into the dataset and call that independent verification.

Treat a correct label supported by incorrect reasoning as defective supervision. Do not infer control, ownership, or entity membership from a single transfer, counterparty, funder, token holding, or explorer label.

## Quality verdict

Use one of:

- `verified`: material claims match independent evidence;
- `verified_with_caveats`: mechanics match but attribution or completeness remains uncertain;
- `contradicted`: at least one material claim conflicts with evidence;
- `insufficient_evidence`: the available surfaces cannot support the claim.

Tell the user about contradictions and missing evidence. Repair fixable code, schema, or derivation defects, regenerate the affected output, and verify the fresh result. Preserve the original record. Append the verification result or superseding revision; never silently rewrite accumulated adjudication data.
