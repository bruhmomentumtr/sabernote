import 'package:saber/components/settings/cloud_profile.dart';

abstract class TestUser {
  static Quota getQuota() {
    const total = 5 * 1024 * 1024 * 1024; // 5 GB
    const usedRatio = 1 - 1 / 1.61803;
    final usedBytes = (total * usedRatio).round();
    return Quota(limit: total, usage: usedBytes, usageInDrive: usedBytes);
  }
}
