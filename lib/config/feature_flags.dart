/// Temporary offline licensing can be removed without changing business data.
const enableLocalLicense = bool.fromEnvironment(
  'ENABLE_LOCAL_LICENSE',
  defaultValue: false,
);
const localLicensePublicKey = String.fromEnvironment(
  'LOCAL_LICENSE_PUBLIC_KEY',
);

/// Reserved for the 2.0 release. Keep stored knowledge data in 1.0.
const enableKnowledgeHub = bool.fromEnvironment(
  'ENABLE_KNOWLEDGE_HUB',
  defaultValue: false,
);
