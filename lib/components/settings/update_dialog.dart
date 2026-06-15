// 🤖 Modified with Claude Sonnet 4.6; Google Antigravity (disabled for fork)
//
// UpdateDialog is never shown in this fork because UpdateManager.showUpdateDialog
// is fully stubbed out. This file is kept as a minimal stub so that any
// remaining import references in the codebase still compile.

import 'package:flutter/material.dart';

/// Stub widget — never displayed in this fork.
/// Update checking is disabled; see [UpdateManager].
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
