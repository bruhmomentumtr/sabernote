/// 🤖 Generated wholely or partially with GPT-5 Codex; OpenAI
library;

import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:saber/components/settings/app_info.dart';
import 'package:saber/data/google_drive/google_drive_client.dart';
import 'package:saber/data/google_drive/login_flow.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:url_launcher/url_launcher.dart';

class NcLoginStep extends StatefulHookWidget {
  const NcLoginStep({super.key, required this.recheckCurrentStep});

  final void Function() recheckCurrentStep;

  @override
  State<NcLoginStep> createState() => _NcLoginStepState();
}

class _NcLoginStepState extends State<NcLoginStep> {
  static const width = 400.0;

  Future<void> _startGoogleLogin({
    required String clientId,
    required String clientSecret,
    required ValueNotifier<bool> isLoading,
    required ValueNotifier<String> errorMessage,
  }) async {
    errorMessage.value = '';
    isLoading.value = true;

    try {
      stows.googleDriveClientId.value = clientId.trim();
      stows.googleDriveClientSecret.value = clientSecret.trim();

      final flow = GoogleDriveLoginFlow(
        clientId: stows.googleDriveClientId.value,
        clientSecret: stows.googleDriveClientSecret.value,
      );
      final result = await flow.start();

      stows.url.value = '';
      stows.ncPassword.value = '';
      stows.username.value = result.profile.email;
      stows.googleDriveAccessToken.value = result.accessToken;
      stows.googleDriveRefreshToken.value = result.refreshToken;
      stows.googleDriveAccessTokenExpiry.value = result.accessTokenExpiresAt
          .toIso8601String();
      stows.googleDriveFolderId.value = '';
      stows.encPassword.value = '';
      stows.key.value = '';
      stows.iv.value = '';

      final client = GoogleDriveClient.withSavedDetails();
      stows.pfp.value = await client?.getProfilePictureBytes(
        result.profile.pictureUrl,
      );

      widget.recheckCurrentStep();
    } catch (e) {
      errorMessage.value = '$e';
    } finally {
      isLoading.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientIdController = useTextEditingController(
      text: stows.googleDriveClientId.value,
    );
    final clientSecretController = useTextEditingController(
      text: stows.googleDriveClientSecret.value,
    );
    final isLoading = useState(false);
    final errorMessage = useState('');

    final hasClientId = useListenableSelector(
      clientIdController,
      () => clientIdController.text.trim().isNotEmpty,
    );

    final colorScheme = ColorScheme.of(context);
    final textTheme = TextTheme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    return ListView(
      padding: .symmetric(
        horizontal: screenWidth > width ? (screenWidth - width) / 2 : 16,
        vertical: 16,
      ),
      children: [
        const SizedBox(height: 16),
        if (screenHeight > 500) ...[
          SvgPicture.asset(
            'assets/images/undraw_cloud_sync_re_02p1.svg',
            width: width,
            height: min(width * 576 / 844.6693, screenHeight * 0.25),
            excludeFromSemantics: true,
          ),
          SizedBox(height: min(64, screenHeight * 0.05)),
        ],
        Text('Google Drive', style: textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Enter your Google Drive API credentials, then continue in the Google sign-in page.',
        ),
        const SizedBox(height: 8),
        Text.rich(
          t.login.form.agreeToPrivacyPolicy(
            linkToPrivacyPolicy: (text) => TextSpan(
              text: text,
              style: TextStyle(color: colorScheme.primary),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  launchUrl(AppInfo.privacyPolicyUrl);
                },
            ),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: clientIdController,
          autocorrect: false,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(
            labelText: 'Google OAuth Client ID',
            hintText: '1234567890-xxxxx.apps.googleusercontent.com',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: clientSecretController,
          autocorrect: false,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(
            labelText: 'Google OAuth Client Secret (optional)',
          ),
        ),
        const SizedBox(height: 6),
        if (errorMessage.value.isNotEmpty)
          Text(errorMessage.value, style: TextStyle(color: colorScheme.error)),
        const SizedBox(height: 6),
        ElevatedButton(
          onPressed: (!hasClientId || isLoading.value)
              ? null
              : () => _startGoogleLogin(
                  clientId: clientIdController.text,
                  clientSecret: clientSecretController.text,
                  isLoading: isLoading,
                  errorMessage: errorMessage,
                ),
          child: Text(
            isLoading.value ? 'Please wait...' : 'Sign in with Google',
          ),
        ),
      ],
    );
  }
}
