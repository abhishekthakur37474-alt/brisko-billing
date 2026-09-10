# Brisko Billing

Point of sale and billing application for the Brisko Pizza outlet. Single outlet,
single billing terminal, primarily online with offline-capable billing.

## Status

Project skeleton only. The architecture, theme and navigation shell are in place.
No feature module is implemented yet, and no backend is connected.

## Structure

```
lib/
  main.dart                  entry point
  app/                       root widget, routes, navigation shell
  core/                      cross-cutting infrastructure
    constants/
    theme/
    error/                   AppFailure hierarchy
    utils/                   Result type, device-side id generation
    data/                    storage and synchronisation contracts
      sync/
      connectivity/
  features/<feature>/        one folder per business capability
    presentation/screens/
  shared/widgets/            widgets reused across features
```

Feature folders gain `domain/` and `data/` subfolders as each module is built.

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
