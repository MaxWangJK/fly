/// Temporary offline licensing can be removed without changing business data.
const enableLocalLicense = bool.fromEnvironment(
  'ENABLE_LOCAL_LICENSE',
  defaultValue: false,
);
const localLicensePublicKey = String.fromEnvironment(
  'LOCAL_LICENSE_PUBLIC_KEY',
);

/// Desktop book library. Phone navigation remains unchanged.
const enableKnowledgeHub = bool.fromEnvironment(
  'ENABLE_KNOWLEDGE_HUB',
  defaultValue: true,
);
