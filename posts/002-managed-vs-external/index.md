---
title: "Managed vs external tables in Hive 3: who owns the files?"
published: false
description: "DROP TABLE is not a syntax detail in Hive 3. It either deletes your product or leaves orphan files on the lake, depending on one word you wrote years ago in DDL."
tags: [hive, dataengineering, hive3, tables]
canonical_url:
---

Two cutovers, two opposite failures, same root cause.

In the first, we needed a full reload of five years of history for a
partner-facing interface. The playbook was familiar: `DROP TABLE`, recreate the
DDL, run the backfill. The table was **external**, but the steps were written like
a managed refresh: drop the name, load again, validate against upstream. `DROP
TABLE` succeeded; nobody deleted the files at the declared `LOCATION`. The reload
landed on top of the old prefix. Row counts and key checks against upstream failed,
not because the new extract was wrong, but because queries were reading **old and
new files together**. After someone cleared the prefix manually, we registered the
table again and ran the five-year load **twice**. Same root mistake: on external
tables, `DROP TABLE` does not empty files on disk.

In the second, we dropped a **managed** mart during data cleanup, assuming an old
copy nobody used. A downstream job still read it. `DROP TABLE` removed the
metastore row and deleted the data under the warehouse path. We ran `CREATE TABLE`
again with the same DDL. The errors went away, but the table was empty. We
restored from backup. On managed tables, `DROP TABLE` deletes files on disk, not
just the catalog entry.

*Disclosure: I used an AI assistant to help draft and structure this write-up.
The operational patterns and review checklist are drawn from production DDL
reviews; the opening incidents are composites, not single tickets.*

Hive makes you choose managed vs external in DDL (or you inherit a choice from
whoever wrote the script years ago). The decision is whether **drop and recreate
should erase the data on disk**: with a **managed** table it usually does; with an
**external** table it does not.

## The design question (standards and exceptions)

Platform standards should answer this for most tables: paths where upstream drops
files **external**, tables your team owns in the warehouse **managed**. When the
work does not fit that pattern (new interface, shared storage prefix, data
cleanup, or full reload), answer this before anyone runs the DDL:

> If we remove the table from the catalog, should the underlying files disappear?

| Answer | Table type | What you are saying |
|--------|------------|---------------------|
| **Yes** | **Managed** | We own the bytes. Dropping the name may delete data under the warehouse path. |
| **No** | **External** | Something else owns the bytes. The Hive name is a pointer at a fixed `LOCATION`. |

At boundaries (upstream feeds, retention, shared lake prefixes), confirm file
ownership with the team that writes or pays for that storage, not for every
internal mart.

```mermaid
flowchart TD
  Q1["If the catalog entry goes away,<br/>should the files go away too?"]
  Q1 -->|Yes| M["Managed table"]
  Q1 -->|No| E["External table"]
  M --> M2["DROP removes metadata and warehouse data"]
  E --> E2["DROP removes metadata only"]
```

ACID, compaction, `MSCK REPAIR`, and cross-engine `DELETE` behaviour all tie
back to the same ownership split; the sections below spell those out.

## At a glance

| | **Managed** | **External** |
|---|-------------|--------------|
| **DDL** | `CREATE TABLE ...` | `CREATE EXTERNAL TABLE ... LOCATION '...'` |
| **Default path** | Under metastore warehouse dir | Path you declare |
| **`DROP TABLE`** | Metadata + table data removed (trash/PURGE per distro) | Metadata only; files stay |
| **Typical zone** | Curated marts, modeled dims/facts | Landing, partner feeds, shared lake prefixes |
| **Who owns bytes** | Your data team / warehouse | Often upstream or platform |

## Managed tables: the platform owns the default path

A **managed** table is the default when DDL says `CREATE TABLE` without
`EXTERNAL`. Data is stored under the warehouse directory configured on the
metastore (`hive.metastore.warehouse.dir` on older clusters; cloud connectors
use equivalent default prefixes on ADLS, S3, or GCS).

**Business fit**

- **Analytics products you control:** conformed dimensions, facts, staging built
  only by your pipelines.
- **Clear accountability:** decommissioning includes `DROP TABLE` and reclaiming
  space.

**What operators actually run**

```sql
CREATE TABLE analytics.dim_channel (
  channel_key   INT,
  channel_name  STRING
)
STORED AS ORC;
```

`CREATE TABLE AS SELECT` and `CREATE TABLE ... AS SELECT` without `EXTERNAL`
also create **managed** tables unless your session overrides say otherwise, a
common surprise when a one-off CTAS lands in the warehouse and nobody remembers
to externalise it.

`INSERT OVERWRITE` on a managed table replaces the dataset in place under that
warehouse path. Consumers see one logical name; the storage location is Hive's
problem.

When you `DROP TABLE` on managed, Hive drops metadata and deletes the table's
warehouse data. Distributions may route deletes through trash; `DROP TABLE ...
PURGE` skips trash on managed tables where supported. That is what you want when
retiring **your** mart. It is what you must not run when you only meant to
unregister a landing alias.

## External tables: metadata points at existing files

**External** tables are declared with `CREATE EXTERNAL TABLE ... LOCATION '...'`.
The metastore holds schema and partition columns; **bytes live at the location**,
often written first by ingestion.

**Business fit**

- **Landing boundaries:** upstream drops files; Hive registers them.
- **Shared lake trees:** one Parquet layout, many readers; dropping one Hive
  name must not wipe the canonical copy.
- **Compliance:** catalog can go; evidence on disk stays until retention policy
  says otherwise.
- **Migration:** register legacy paths while rewrite jobs catch up.

```sql
CREATE EXTERNAL TABLE landing.raw_orders (
  order_id    STRING,
  order_ts    TIMESTAMP
)
PARTITIONED BY (dt STRING)
STORED AS PARQUET
LOCATION 's3://data-lake/landing/orders/';
```

`DROP TABLE landing.raw_orders` removes the metastore entry **only**. Files at
`LOCATION` stay until something else deletes or overwrites them. That is the
failure mode in the first opening story.

On newer distros, `external.table.purge=true` makes `DROP TABLE` delete external
data too. Check `DESCRIBE FORMATTED` for that property and your Hive version
before you assume files will stay.

External tables need `MSCK REPAIR TABLE` or explicit partition adds when new
directories land before the catalog is updated. Because the real data lives on
disk and not only in Hive, you maintain partitions yourself; that maintenance is
the cost of choosing external.

```mermaid
flowchart LR
  subgraph upstream [Upstream]
    U1[Scheduled file drops]
  end
  subgraph landing [Landing]
    L1[EXTERNAL tables]
  end
  subgraph curated [Curated]
    C1[MANAGED tables]
  end
  U1 --> L1
  L1 -->|transform| C1
```

## What this is not

**Neither choice is inherently faster or more secure.** Formats, partitioning,
file sizes, and skew dominate read cost. IAM and policy dominate security.
People sometimes pick external hoping reads will be faster. Usually they mean
**the files are already on the lake** and Hive only registers them, so the
pipeline skips copying into the warehouse. `EXTERNAL` by itself does not speed up
queries.

**Managed vs external is not a substitute for agreeing with other teams.** At the
edge (partner or upstream feeds), the external table is often just a catalog name
over a folder someone else writes. The real agreement is the **path**, **file
format**, and **layout** (columns and partition folders). In the curated
warehouse, the managed table is usually the **official dataset** analysts query.
The real agreement is the **schema**, **grain**, and **refresh** they rely on.

## Three mistakes I see in production reviews

**1. `DROP` without `DESCRIBE FORMATTED`**

Before a cleanup sprint, print type and location:

```sql
DESCRIBE FORMATTED analytics.dim_channel;
DESCRIBE FORMATTED landing.raw_orders;
```

Look for `Table Type: MANAGED_TABLE` vs `EXTERNAL_TABLE` and the `Location:` line.
If that does not match what the ticket says, stop.

**2. Shared `LOCATION` prefixes**

Two external tables (or one external and one sloppy `INSERT`) pointed at the same
prefix make overwrite or bulk delete a **cross-team incident**. External is not
"safer"; it is **shared ownership of a path**.

**3. CTAS by default in the warehouse**

Ad hoc `CREATE TABLE … AS SELECT` creates managed tables in the default database
unless you externalise on purpose. Six months later nobody remembers, and `DROP`
deletes work somebody thought was "just a temp extract."

## Before you DROP (five-minute checklist)

Run this on every cleanup ticket, not only "big" tables:

1. `DESCRIBE FORMATTED schema.table;`
2. Read **`Table Type:`** (`MANAGED_TABLE` vs `EXTERNAL_TABLE`).
3. Read **`Location:`** and ask who else might write or delete under that prefix.
4. Compare to the ticket: "remove catalog entry" vs "reclaim storage."
5. If managed and you only meant to unregister, **`DROP` is the wrong tool**. Use
   rename, archive policy, or an external pointer instead.

If step 2 and step 4 disagree, stop and escalate. That mismatch is how both
opening incidents happened.

## Hive 3 wrinkles worth knowing

**Transactional (ACID) tables.** In Hive 3, **external tables are not
transactional.** Native ACID (`UPDATE`/`DELETE`/`MERGE`, compaction, consistent
snapshots) needs Hive to own and rewrite the data files. On an external table the
bytes live at a `LOCATION` outside that control, so making an external table ACID
is disallowed ([HIVE-13175][h13175]). Full ACID assumes layouts Hive manages.
Marts that need row-level change belong in **managed transactional** tables in a
curated schema, not on a shared landing prefix.

**Renames and `ALTER TABLE SET LOCATION`.** `RENAME TABLE` changes names in the
metastore. On a **managed** table, Hive may also adjust the warehouse folder
layout, because it owns that storage. On an **external** table, the name in the
catalog changes, but the files stay at the same `LOCATION` until you move them
yourself.

`ALTER TABLE … SET LOCATION '…'` updates the pointer in the metastore. It does
**not** copy or move files. The usual migration pattern is copy data to the new
prefix, verify counts, then run `SET LOCATION` so Hive reads the new path. If you
only rename the table or change `LOCATION` and assume the bytes moved, queries
can hit an empty folder or the wrong prefix while the real data sits elsewhere.

**Cloud warehouses.** Warehouse dir and `LOCATION` are URLs. The business question
is unchanged: who may delete the prefix when the catalog entry disappears?

## A workshop line that lands with non-engineers

Draw three zones on a whiteboard:

```text
landing/     EXTERNAL  upstream owns bytes; we register and read
curated/     MANAGED   we own model + lifecycle
archive/     EXTERNAL  long retention; catalog optional
```

```mermaid
flowchart LR
  subgraph upstream [Upstream systems]
    U1[Files land on schedule]
  end

  subgraph landing [Landing zone]
    L1[EXTERNAL tables]
    L2[LOCATION fixed by contract]
  end

  subgraph curated [Curated warehouse]
    C1[MANAGED tables]
    C2[Model owned by data team]
  end

  subgraph consumers [Consumers]
    X1[BI and notebooks]
    X2[Downstream pipelines]
  end

  U1 --> L1
  L1 -->|transform jobs| C1
  C1 --> X1
  C1 --> X2
```

Your company may not name folders that way. The **ownership line between landing
and curated** is where managed vs external arguments actually get decided.

## Spark and Delta use the same question

Spark SQL and Delta expose the same tension under different words: default
`saveAsTable` paths vs `path '...'` on `CREATE TABLE`, external locations on
shared ADLS prefixes, `DROP TABLE` vs `DELETE` on Delta. The vocabulary changes;
**who may delete the directory when the table name goes away** does not. If you
only remember one sentence for a multi-engine lake, remember that one.

## What is measured here, and what is not

The **DROP / EXTERNAL / managed** behaviour is documented in Hive's
[LanguageManual DDL][langddl]. Vendor distros add trash, export, and Ranger hooks.
Verify on your cluster before a production `DROP`.

The **two opening incidents** are composites of common mistakes (external reload
without clearing `LOCATION` after `DROP`; data loss after managed `DROP`). They are
not one verbatim ticket.

The **zone pattern** is widely described in lake design; your org may invert a
layer for history. The decision question still applies.

DDL and `DESCRIBE FORMATTED` examples for Gist embeds live under
`posts/002-managed-vs-external/gists/` in the blog repo.

## Sources

- [Apache Hive: LanguageManual DDL][langddl]
- [Apache Hive: Hive Transactions (ACID)][acid]
- [Apache Hive: Design documents][designdocs]
- [HIVE-13175: disallow making external tables transactional][h13175]

[langddl]: https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL
[acid]: https://cwiki.apache.org/confluence/display/Hive/Hive+Transactions
[designdocs]: https://hive.apache.org/development/designdocs/
[h13175]: https://issues.apache.org/jira/browse/HIVE-13175
