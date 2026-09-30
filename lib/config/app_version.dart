/// The release script supplies this from pubspec.yaml for packaged builds.
/// The fallback keeps local IDE runs identifiable without an extra dependency.
const flyAppVersion = String.fromEnvironment(
  'FLY_APP_VERSION',
  defaultValue: '1.0.0+24',
);
