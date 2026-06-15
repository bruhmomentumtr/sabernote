// 🤖 Modified with Claude Sonnet 4.6; Google Antigravity (disabled update checks for fork)
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:saber/data/saber_version.dart';
import 'package:saber/data/version.dart' as version;

abstract class UpdateManager {
  static final log = Logger('UpdateManager');

  static final Uri versionUrl = Uri.parse(
    'https://raw.githubusercontent.com/saber-notes/saber/main/lib/data/version.dart',
  );
  static final Uri apiUrl = Uri.parse(
    'https://api.github.com/repos/saber-notes/saber/releases/latest',
  );

  /// The availability of an update.
  static final ValueNotifier<UpdateStatus> status = ValueNotifier(.upToDate);
  static int? newestVersion;

  /// Update checking is fully disabled for this fork.
  /// All calls are stubbed out so no network requests are made
  /// and no update dialog is ever shown.
  static Future<void> showUpdateDialog(
    BuildContext context, {
    bool userTriggered = false,
  }) async {
    // Disabled: this fork does not use the upstream saber-notes/saber releases.
    return;
  }

  static Future<UpdateStatus> _checkForUpdate() async {
    // Update checking is disabled for this fork.
    // The upstream saber-notes/saber repo is not relevant here.
    return .upToDate;
  }

  /// Returns the version number hosted on GitHub (at [versionUrl]).
  /// If you provide a [latestVersionFile] (i.e. for testing),
  /// it will be used instead of downloading from GitHub.
  @visibleForTesting
  static Future<int?> getNewestVersion([String? latestVersionFile]) async {
    latestVersionFile ??= await _downloadLatestVersionFileFromGitHub();

    // extract the number from the latest version.dart
    final RegExp numberRegex = RegExp(r'(\d+)');
    final RegExpMatch? newestVersionMatch = numberRegex.firstMatch(
      latestVersionFile,
    );
    if (newestVersionMatch == null) return null;

    final int newestVersion = int.tryParse(newestVersionMatch[0] ?? '0') ?? 0;
    if (newestVersion == 0) return null;

    return newestVersion;
  }

  static Future<String> _downloadLatestVersionFileFromGitHub() async {
    // download the latest version.dart
    final http.Response response;
    try {
      response = await http.get(versionUrl);
    } catch (e) {
      throw SocketException('Failed to download version.dart, ${e.toString()}');
    }
    if (response.statusCode >= 400)
      throw SocketException(
        'Failed to download version.dart, HTTP status code ${response.statusCode}',
      );

    return response.body;
  }

  @visibleForTesting
  static UpdateStatus getUpdateStatus(
    int currentVersionNumber,
    int newestVersionNumber,
  ) {
    final currentVersion = SaberVersion.fromNumber(
      currentVersionNumber,
    ).copyWith(revision: 0);
    final newestVersion = SaberVersion.fromNumber(
      newestVersionNumber,
    ).copyWith(revision: 0);

    // Check if we're up to date
    if (newestVersion.buildNumber <= currentVersion.buildNumber) {
      return .upToDate;
    }

    // Check if the update is low priority
    if (!stows.shouldAlwaysAlertForUpdates.value) {
      // Only prompt user every second patch
      if (newestVersion.buildNumber - currentVersion.buildNumber <
          SaberVersion.fromName('0.0.2').buildNumber) {
        return .updateOptional;
      }

      // Don't prompt user when patch version is 0 (e.g. 0.15.0)
      // since there might still be bugs to fix
      if (newestVersion.patch == 0) {
        return .updateOptional;
      }
    }

    return .updateRecommended;
  }

  /// Disabled for this fork — always returns null.
  static Future<String?> getLatestDownloadUrl([
    @visibleForTesting String? apiResponse,
    @visibleForTesting TargetPlatform? platform,
  ]) async =>
      null;

  static final Map<TargetPlatform, RegExp> platformFileRegex = {
    // Normal platforms get their updates from app stores, so
    // manual update handling is only needed for Windows.
    .windows: RegExp(r'\.exe'),
  };

  /// Downloads the update file from [downloadUrl] and installs it.
  static Future<void> directlyDownloadUpdate(
    String downloadUrl, {
    required void Function(TaskStatus)? onStatus,
    required void Function(double)? onProgress,
  }) async {
    final fileName = downloadUrl.substring(downloadUrl.lastIndexOf('/') + 1);
    final task = DownloadTask(
      url: downloadUrl,
      filename: fileName,
      baseDirectory: BaseDirectory.temporary,
    );
    await FileDownloader().configure(
      globalConfig: [
        (Config.skipExistingFiles, 1),
        (Config.checkAvailableSpace, 1),
      ],
    );
    final result = await FileDownloader().download(
      task,
      onStatus: onStatus,
      onProgress: onProgress,
    );
    if (result.status == TaskStatus.complete) {
      log.info('Update downloaded successfully: ${result.status}');
      await OpenFile.open(await task.filePath());
    } else {
      log.severe(
        'Failed to download update from $downloadUrl: '
        '${result.status} ${result.exception} ${result.responseBody}',
      );
    }
  }

  /// Disabled for this fork — always returns null.
  static Future<String?> getChangelog({
    String localeCode = 'en-US',
    @visibleForTesting int? newestVersion,
  }) async =>
      null;
}

enum UpdateStatus {
  /// The app is up to date, or we failed to check for an update.
  upToDate,

  /// An update is available, but the user doesn't need to be notified
  updateOptional,

  /// An update is available and the user should be notified
  updateRecommended,
}
