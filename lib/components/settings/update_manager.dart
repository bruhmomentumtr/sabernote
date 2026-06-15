// 🤖 Modified with Claude Sonnet 4.6; Google Antigravity (disabled update checks for fork)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:saber/data/saber_version.dart';
import 'package:saber/data/version.dart' as version;

/// All update-checking functionality is disabled for this fork.
///
/// This fork (bruhmomentumtr/sabernote) has its own versioning and should
/// not compare against or advertise upstream saber-notes/saber releases.
/// Every method is stubbed out so no network requests are ever made and
/// no update dialog is ever shown to the user.
///
/// To re-enable in the future: restore the original upstream file and point
/// [versionUrl] / [apiUrl] at this fork's own GitHub repository.
abstract class UpdateManager {
  static final log = Logger('UpdateManager');

  /// The availability of an update — always [UpdateStatus.upToDate] for
  /// this fork because update checking is disabled.
  static final ValueNotifier<UpdateStatus> status = ValueNotifier(.upToDate);
  static int? newestVersion;

  /// Stubbed out — immediately returns without showing any dialog.
  static Future<void> showUpdateDialog(
    BuildContext context, {
    bool userTriggered = false,
  }) async {
    // Disabled: this fork does not use upstream saber-notes/saber releases.
  }

  /// Stubbed out — always returns [UpdateStatus.upToDate].
  @visibleForTesting
  static Future<UpdateStatus> checkForUpdate() async => .upToDate;

  /// Stubbed out — always returns [UpdateStatus.upToDate].
  @visibleForTesting
  static UpdateStatus getUpdateStatus(
    int currentVersionNumber,
    int newestVersionNumber,
  ) {
    // Keep this method for test compatibility; always report up to date.
    return .upToDate;
  }

  /// Stubbed out — always returns null.
  static Future<String?> getLatestDownloadUrl([
    @visibleForTesting String? apiResponse,
    @visibleForTesting TargetPlatform? platform,
  ]) async =>
      null;

  /// Stubbed out — always returns null.
  static Future<String?> getChangelog({
    String localeCode = 'en-US',
    @visibleForTesting int? newestVersion,
  }) async =>
      null;

  /// Stubbed out — does nothing.
  static Future<void> directlyDownloadUpdate(
    String downloadUrl, {
    required void Function(Object?)? onStatus,
    required void Function(double)? onProgress,
  }) async {
    // Disabled.
  }

  static final Map<TargetPlatform, RegExp> platformFileRegex = {
    .windows: RegExp(r'\.exe'),
  };
}

enum UpdateStatus {
  /// The app is up to date, or we failed to check for an update.
  upToDate,

  /// An update is available, but the user doesn't need to be notified
  updateOptional,

  /// An update is available and the user should be notified
  updateRecommended,
}
