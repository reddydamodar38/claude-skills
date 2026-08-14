# Cross-tier correlation

- Additional Java services and larger JDBC connection pools can increase application-tier RSS and database connection/process memory at the same time.
- Treat that pattern as a supported contributor only after checking service inventory, JVM count, JDBC pool configuration, and observed DB sessions/connections.
- Without those checks, use **consistent with** or **could contribute to**; do not state that JDBC or a TP package caused the increase.
- Stable CPU, response time, paging, GC, and heap headroom support a capacity-footprint conclusion rather than memory pressure.
- Suggested sign-off wording: `The 2.40 GiB average (2.49 GiB maximum) Application-tier increase is consistent with the added Java-service and JDBC-pool footprint; stable CPU, response times, GC, and heap headroom show no resulting memory pressure.`
