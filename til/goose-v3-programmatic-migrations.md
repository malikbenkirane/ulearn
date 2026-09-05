# Auto-migrating a Go app with goose v3 from code (no CLI at runtime)

TLDR;
- author migrations with the goose CLI, embed the migrations directory and hand
an `fs.FS` to `goose.NewProvider(dialect, db, fsys)`,
- call `provider.Up(ctx)` on startup, and skip any tutorial that tells you to
use `goose.SetBaseFS` and `goose.Up(db, dir)`. That is the pre-2023 global-state
API and no longer the recommended path.

Now, if goose is best known as a CLI, the CLI is a thin wrapper around the library.

If your app should run its own migrations on startup, say it keeps a sqlite
file under ~/.cache, you can do it entirely from Go and keep the CLI only for
authoring migration files.

The pattern: migrations live in a `migrations/` package, get embedded in the
binary, and a `Provider` applies them idempotently at startup.

Install the CLI once, for creating files:

```
go install github.com/pressly/goose/v3/cmd/goose@latest
go get github.com/pressly/goose/v3
```

Then create a migration as usual:

```
goose create add_preset_table go
```

This drops a timestamped Go file (e.g. `20240509120000_add_preset_table.go`)
into your migrations dir, with an `init()` that registers up/down functions
defined in the same file.

The migrations are Go code, not SQL files.

Embed the migrations directory at the package that ships the app:

```go
package main

//go:embed migrations
var migrationsFS embed.FS
```

Embedding the directory matters when you ship a standalone binary.

The migration files are compiled in, so the app never reads them from disk at
runtime.

Applying them at startup looks like this:

```go
import (
    "context"
    "database/sql"
    "io/fs"

    "github.com/pressly/goose/v3"
    _ "github.com/glebarez/go-sqlite"  // your driver of choice
    _ "yourmodule/migrations"          // registers Go migrations via init()
)

func migrate(db *sql.DB) error {
    fsys, err := fs.Sub(migrationsFS, "migrations")
    if err != nil {
        return err
    }
    provider, err := goose.NewProvider(goose.DialectSQLite3, db, fsys)
    if err != nil {
        return err
    }
    _, err = provider.Up(context.Background())
    return err
}
```

The dialect constant replaces the old `goose.SetDialect("sqlite")` global.

The third argument is any `fs.FS` that lists the migration files (an `fs.Sub`
of the embedded one, or `os.DirFS("migrations")` for a disk layout).

The blank import pulls in the migrations package so its `init()` registers the
Go migrations with goose's registry, while the provider supplies the dialect,
database, and `fs.FS` of migration sources. `provider.Up(ctx)` runs every
migration that has not been applied yet and records versions in a goose metadata
table (`goose_db_version` by default).

Calling it on every startup is safe and cheap: applied migrations are skipped.

A note on versions. goose v3.16 (November 2023) added `goose.NewProvider`, and
the maintainer's blog post says outright that the Provider is the recommended
way to use goose as a library, with future work targeted at it. The older
globals (`goose.SetDialect`, `goose.SetBaseFS`, `goose.Up(db, dir)`) still work
and were not removed from /v3, but they have real downsides.

Config lives in package-level variables, so two independent goose uses in one
process interfere with each other and concurrent calls are unsafe.

The old `goose.Up` returns only an error; progress was available through
internal logging. The provider returns `[]*goose.MigrationResult`, so you can
log applied versions, handle `goose.PartialError` (it tells you which migration
failed and what state the DB is in), or emit a JSON report.

Logging becomes configurable with `goose.WithSlog(logger)` instead of the
package writing to its own logger. `goose.WithSessionLocker(...)` guards against
two instances racing to migrate the same database.

Since nothing is global anymore, tests are simple. In-memory sqlite plus any
`fs.FS`:

```go
db, _ := sql.Open("sqlite", ":memory:")
p, err := goose.NewProvider(goose.DialectSQLite3, db, fsys)
if err != nil { t.Fatal(err) }
res, err := p.Up(context.Background())
if err != nil { t.Fatal(err) }
if len(res) == 0 { t.Fatal("expected migrations to run") }
```

`p.ListSources()`, `p.Status(ctx)` and `p.GetDBVersion(ctx)` cover state
assertions.

Further reading: https://pressly.github.io/goose/blog/2023/goose-provider/
