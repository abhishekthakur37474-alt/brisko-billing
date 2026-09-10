# Brisko Billing

Point of sale and billing application for the Brisko Pizza outlet. Single outlet,
single billing terminal, primarily online with offline-capable billing.

## Status

Data foundation complete, and the real menu is loaded. The SQLite schema,
migrations, domain models, repositories and the full Brisko Pizza menu are in place
and tested. No screen is implemented beyond the navigation shell, and no cloud
backend is connected.

The seed holds 12 categories, 64 products, 55 size variants and 171 option rows,
transcribed from the outlet's printed menu. Two prices are absent because the menu
does not print them; see `MenuSeedData.pendingFromMenuImage`.

## Menu option scope

An option's price often depends on the size chosen: Extra Cheese is ₹50 on a Small
and ₹90 on a Large. That is expressed as relationships, never as text in the name.
`menu_item_options` carries three nullable scope columns, narrowest first:

| Column set | Applies to |
|---|---|
| `variantId` | one exact size of one product |
| `menuItemId` | one product, any size |
| `categoryId` | every product in a category |
| none | every product |

Callers do not read these. `MenuRepository.loadOptionsForVariant` takes the chosen
variant and returns a ready list at the right prices, combining all four scopes and
letting the narrowest win where a name is reachable through several.
`loadOptionsForItem` is for products sold at a single price and deliberately excludes
size-dependent options, whose price is undefined without a size.

Because a variant row exists per product and size, there is no shared "Small" to
point at, so the ten priced option cells on the menu expand to 170 rows across the
seventeen pizzas, plus Ketchup as the only global option.

## Structure

```
lib/
  main.dart                  entry point
  app/                       root widget, routes, shell, dependency wiring
  core/                      cross-cutting infrastructure
    constants/
    theme/
    error/                   AppFailure hierarchy
    money/                   Money value type (integer paise)
    utils/                   Result type, device-side id generation
    data/
      local_store.dart       storage contract
      remote_store.dart      cloud contract
      local/sqlite/          the only place SQL lives
        migrations/
        seed/
      remote/                no-op remote until a backend exists
      sync/                  outbox and sync contracts
      connectivity/
  features/<feature>/        one folder per business capability
    domain/models/
    domain/repositories/     abstract contract
    data/repositories/       SQLite implementation
    presentation/screens/
  shared/widgets/            widgets reused across features
```

## Money and quantities

Money is an exact integer count of **paise**, wrapped in `Money`. Columns holding it
are `INTEGER` and suffixed `Paise`. `double` is never used for money: binary floating
point cannot represent most decimal fractions, so a bill summing many lines would
drift and produce a legally incorrect GST invoice.

Tax and discount rates are integer **basis points** (10000 = 100%). Rounding happens
in exactly one place, `Money.applyRate`, half away from zero.

Fractional stock quantities are integer **thousandths** of the unit, in columns
suffixed `Milli`, for the same reason.

## Historical accuracy

Order lines, line options and kitchen slip lines store name and price *snapshots*
taken at the moment of sale. Nothing recomputes a historical bill from the menu
tables, so re-pricing or renaming a product cannot alter a bill that has already
been printed.

Deletion is soft everywhere (`isDeleted`), so a record removed offline can still tell
the cloud it was removed, and so history stays auditable.

## Architecture

Feature-first, with a thin layered split inside each feature.

- Widgets render state and raise intent. They contain no business rules and no
  data access.
- `ChangeNotifier` controllers hold presentation state, exposed through
  `provider`. Dependencies are wired in one place, `lib/app/brisko_app.dart`.
- Repositories return `Result<T>` rather than throwing, so callers must handle
  failure.
- Local storage is the source of truth for writes. Every write also appends an
  entry to a durable outbox. A sync coordinator replays that outbox to the cloud
  when connectivity allows, pushing before pulling and resolving collisions by
  `updatedAt`.

That last point is why billing keeps working when the internet drops: the billing
module writes locally and enqueues, and never waits on or asks about the network.

## Commands

```sh
flutter pub get
flutter analyze
flutter test
flutter build macos --debug
```
