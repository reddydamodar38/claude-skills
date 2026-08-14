# Data model

## Tables

### prg_metadata
- `file_path`
- `script_name`
- `request_number`
- `product`

### tdb_metadata
- `request_number`
- `request_name`
- `request_type`
- `service_binding`

### scp_definitions
- `scp_number`
- `server_name`
- `service`
- `service_binding`

### workflow_records
- `workflow_file`
- `workflow_name`
- `yaml_path`
- `field_name`
- `field_value`
- `request_number`
- `transaction_name`
- `script_name`
- `service_binding`
- `server_name`
- `step_name`
- `raw_context`

## Join chain

Use request number first, then binding, then workflow references:

`prg_metadata.request_number -> tdb_metadata.request_number -> scp_definitions.service_binding -> workflow_records.(request_number|transaction_name|script_name|service_binding)`

## Evidence rules

- Store both raw and normalized values.
- Treat blank values and `tba` as missing.
- Keep one-to-many mappings instead of forcing a single winner.
