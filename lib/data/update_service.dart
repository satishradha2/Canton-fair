import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateInfo {
  final bool updateAvailable;
  final String currentVersion;
  final String latestVersion;
  final String releaseUrl;
  final String? apkUrl;

  const AppUpdateInfo({
    required this.updateAvailable,
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    this.apkUrl,
  });
}

class UpdateService {
  static const _latestReleaseApi =
      'https://api.github.com/repos/satishradha2/Canton-fair/releases/latest';

  Future<AppUpdateInfo> checkLatest() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

    final response = await http.get(
      Uri.parse(_latestReleaseApi),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('GitHub update check failed (${response.statusCode})');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final tagName =
        (payload['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^v'), '');
    final releaseUrl = payload['html_url'] as String? ??
        'https://github.com/satishradha2/Canton-fair/releases/latest';
    final assets =
        (payload['assets'] as List? ?? []).whereType<Map<String, dynamic>>();
    final apkAsset = assets.cast<Map<String, dynamic>?>().firstWhere(
          (asset) =>
              (asset?['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
          orElse: () => null,
        );
    final apkUrl = apkAsset?['browser_download_url'] as String?;

    return AppUpdateInfo(
      updateAvailable: _isRemoteNewer(currentVersion, tagName),
      currentVersion: currentVersion,
      latestVersion: tagName.isEmpty ? 'unknown' : tagName,
      releaseUrl: releaseUrl,
      apkUrl: apkUrl,
    );
  }

  bool _isRemoteNewer(String current, String latest) {
    final versionComparison = _compareVersionNames(current, latest);
    if (versionComparison != 0) return versionComparison < 0;

    final currentBuild = _buildNumber(current);
    final latestBuild = _buildNumber(latest);
    if (currentBuild != null && latestBuild != null) {
      return latestBuild > currentBuild;
    }
    return latest.isNotEmpty && latest != current;
  }

  int _compareVersionNames(String current, String latest) {
    final currentParts = current.split('+').first.split('.');
    final latestParts = latest.split('+').first.split('.');
    if (currentParts.any((part) => int.tryParse(part) == null) ||
        latestParts.any((part) => int.tryParse(part) == null)) {
      return 0;
    }

    final length = currentParts.length > latestParts.length
        ? currentParts.length
        : latestParts.length;
    for (var index = 0; index < length; index++) {
      final currentPart =
          index < currentParts.length ? int.parse(currentParts[index]) : 0;
      final latestPart =
          index < latestParts.length ? int.parse(latestParts[index]) : 0;
      if (currentPart != latestPart) return currentPart.compareTo(latestPart);
    }
    return 0;
  }

  int? _buildNumber(String version) {
    final parts = version.split('+');
    if (parts.length < 2) return null;
    return int.tryParse(parts.last);
  }
}
