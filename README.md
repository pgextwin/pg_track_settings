# pg_track_settings — Windows x64

pgextwin is the issuer for **unofficial Windows x64 builds** of [pg_track_settings](https://github.com/rjuju/pg_track_settings), packaged from the official upstream source (`2.1.2`, commit `36a23f3c6d684c40140da1a24b1c3ee0e707b77a`). pg_track_settings tracks PostgreSQL configuration and per-database/role setting changes over time, along with server restart timestamps.

## Compatibility

Target PostgreSQL majors for this repository: **15–18** (`windows-x64`).

`pg_track_settings` is a **SQL-only extension** (`default_version = '2.1.2'`) with no native DLL and no `shared_preload_libraries` requirement.

## Installation

1. Back up your installation and review the [upstream pg_track_settings documentation](https://github.com/rjuju/pg_track_settings).
2. Extract the ZIP matching your PostgreSQL major and copy `share/extension/` contents (`pg_track_settings.control` and `pg_track_settings--*.sql`) into your PostgreSQL `share/extension/` directory.
3. Run `CREATE EXTENSION pg_track_settings;` in each database that needs the extension.

## License

This is an independent, unofficial Windows package; see [LICENSE](LICENSE) for the upstream license notice.
