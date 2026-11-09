/// Official public services stay independent of account and LAN configuration.
abstract final class FlyServiceEndpoints {
  static const officialApiBaseUrl = 'https://world-workshop.cn/api';
  static Uri get analyticsBaseUrl => Uri.parse(officialApiBaseUrl);
  static Uri get updatesBaseUrl => Uri.parse(officialApiBaseUrl);

  static Uri endpoint(Uri base, List<String> parts) => base.replace(
    pathSegments: [
      ...base.pathSegments.where((part) => part.isNotEmpty),
      ...parts,
    ],
  );
}
