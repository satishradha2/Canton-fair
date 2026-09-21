import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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

class ApkDownloadProgress {
  final int receivedBytes;
  final int? totalBytes;

  const ApkDownloadProgress(this.receivedBytes, this.totalBytes);

  double? get fraction =>
      totalBytes == null || totalBytes == 0 ? null : receivedBytes / totalBytes!;
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

  /// Downloads the APK inside the app, verifies the file, and then opens the
  /// Android package installer. This avoids browser/download-manager stalls.
  Future<void> downloadAndInstall(
    AppUpdateInfo update, {
    void Function(ApkDownloadProgress progress)? onProgress,
  }) async {
    final url = update.apkUrl;
    if (url == null || url.isEmpty) {
      throw StateError('The latest release does not contain an APK download.');
    }

    final cache = await getTemporaryDirectory();
    final updateDirectory = Directory('${cache.path}${Platform.pathSeparator}updates');
    await updateDirectory.create(recursive: true);
    final safeVersion = update.latestVersion.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final file = File('${updateDirectory.path}${Platform.pathSeparator}canton-fair-$safeVersion.apk');
    if (await file.exists()) await file.delete();

    final request = http.Request('GET', Uri.parse(url))
      ..followRedirects = true
      ..maxRedirects = 5;
    final response = await request.send().timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('APK download failed (${response.statusCode}).');
    }

    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(const Duration(seconds: 45))) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(ApkDownloadProgress(received, response.contentLength));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (received < 4096 ||
        (response.contentLength != null && received != response.contentLength)) {
      throw StateError('The APK download was incomplete. Please retry on a stable connection.');
    }
    final header = await file.openRead(0, 4).fold<List<int>>([], (bytes, chunk) {
      bytes.addAll(chunk);
      return bytes;
    });
    if (header.length < 4 || header[0] != 0x50 || header[1] != 0x4B) {
      throw StateError('The downloaded file is not a valid APK. Please retry later.');
    }

    await const MethodChannel('canton_fair_crm/updater')
        .invokeMethod<void>('installApk', {'path': file.path});
  }
}
