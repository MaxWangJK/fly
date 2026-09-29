/// Temporary offline licensing can be removed without changing business data.
const enableLocalLicense = bool.fromEnvironment(
  'ENABLE_LOCAL_LICENSE',
  defaultValue: false,
);
const localLicensePublicKey = String.fromEnvironment(
  'LOCAL_LICENSE_PUBLIC_KEY',
);
