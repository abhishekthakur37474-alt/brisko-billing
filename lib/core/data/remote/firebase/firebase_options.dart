import 'firebase_config.dart';

/// The application's Firebase project configuration.
///
/// ## Why this is application configuration, not restaurant settings
///
/// A restaurant owner configures their outlet — its name, GSTIN, GST rate, printer.
/// They do not configure which Firebase project the build talks to, any more than they
/// configure the app's package name. The Firebase project id and the client-safe Web API
/// key are decided once, by whoever ships the build, and are the same for every terminal
/// of that build. So they live here, baked into the application, and never in the
/// settings table or behind a text field on the Settings screen.
///
/// ## Where the values come from
///
/// From `--dart-define` at build time:
///
/// ```
/// flutter build macos --dart-define=BRISKO_FIREBASE_PROJECT_ID=brisko-pos \
///                     --dart-define=BRISKO_FIREBASE_API_KEY=AIza...
/// ```
///
/// Both are **client-safe** by design: a Firebase Web API key and project id are meant to
/// ship in client applications. They grant nothing on their own — access is controlled by
/// Firestore Security Rules on the server, which require a signed-in user whose `uid`
/// matches the restaurant document. The privileged service-account key is never part of
/// the application, in configuration or in source.
///
/// ## The default is "no cloud"
///
/// Left undefined — as in a plain `flutter run` or the test suite — both values are empty
/// and [isConfigured] is false. The terminal then runs **purely local**: every change is
/// saved to SQLite and queued, exactly the offline-first behaviour the rest of the
/// architecture already handles. This is why a developer build and every widget test
/// behave as a local-only till without any cloud wiring.
class FirebaseOptions {
  const FirebaseOptions({required this.projectId, required this.apiKey});

  /// The Firebase project id, for example `brisko-pos`.
  final String projectId;

  /// The client-safe Web API key (Firebase console → Project settings → General).
  final String apiKey;

  /// True when the build carries a Firebase project to talk to. False means the build is
  /// local-only and the login gate is skipped entirely.
  bool get isConfigured =>
      projectId.trim().isNotEmpty && apiKey.trim().isNotEmpty;

  /// A [FirebaseConfig] for this project, carrying the signed-in session's
  /// [refreshToken] when the terminal has one. The refresh token is not part of the
  /// build: it is a per-terminal session, obtained by signing in and persisted locally.
  FirebaseConfig toConfig({String? refreshToken}) => FirebaseConfig(
    projectId: projectId,
    apiKey: apiKey,
    refreshToken: refreshToken,
  );

  /// The configuration this build was compiled with.
  ///
  /// Reads the two client-safe values from the compile-time environment, so the same
  /// source produces a local-only build by default and a cloud-connected build when the
  /// project is supplied at build time.
  static const FirebaseOptions current = FirebaseOptions(
    projectId: String.fromEnvironment('BRISKO_FIREBASE_PROJECT_ID'),
    apiKey: String.fromEnvironment('BRISKO_FIREBASE_API_KEY'),
  );
}
