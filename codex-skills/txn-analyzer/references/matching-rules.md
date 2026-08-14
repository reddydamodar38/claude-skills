# Matching rules

## Exact matches

Prefer exact joins on:
- request number
- service binding
- script name
- transaction name
- server or service name

## Inference rules

Use inference only when explicit data is missing:
- script file path name resembles script name
- scenario YAML names a request or script without a direct join key
- server/service is implied by a binding but not named directly

## Confidence guidance

- 1.00: exact request number or exact binding
- 0.95: exact script or transaction name
- 0.85: workflow file directly names the same request or script
- 0.70: naming convention only
- 0.50: weak heuristic match

## Investigation guidance

When a transaction is slow, rank the likely causes in this order:
1. workflow branch / dependency chain
2. script or query logic
3. server or service routing
4. database wait or SQL issue
