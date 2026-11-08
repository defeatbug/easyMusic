import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../plugin/sign_in.dart';
import 'theme.dart';

/// The QR sign-in overlay: while the plugin's signIn() runs, its
/// host.signInPrompt updates land in the [SignInPromptController] and
/// are rendered here — a QR image (the plugin's payload is the login
/// URL the service's app scans) over its status line, with a cancel
/// button that abandons the host call. Rendered in the shell's stack,
/// so both layouts get it and the prompt updates in place.
class SignInOverlay extends StatelessWidget {
  const SignInOverlay({
    super.key,
    required this.controller,
    required this.onCancel,
  });

  final SignInPromptController controller;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final prompt = controller.prompt;
        if (!controller.visible || prompt == null) {
          return const SizedBox.shrink();
        }
        return Positioned.fill(
          child: ColoredBox(
            color: const Color.fromRGBO(0, 0, 0, 0.38),
            child: Center(
              child: Container(
                width: 320,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
                decoration: BoxDecoration(
                  color: Palette.bg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '登录网易云音乐',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: Palette.text,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (prompt.qr.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Palette.hairline),
                        ),
                        child: QrImageView(
                          data: prompt.qr,
                          version: QrVersions.auto,
                          size: 208,
                        ),
                      )
                    else
                      const SizedBox(
                        height: 120,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Palette.accent,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      prompt.text.isEmpty ? '请用网易云音乐 App 扫码登录' : prompt.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: Palette.muted,
                      ),
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton(
                      onPressed: onCancel,
                      child: const Text('取消登录'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
