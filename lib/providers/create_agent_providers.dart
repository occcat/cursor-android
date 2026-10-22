/// Starting a cloud agent from the New agent page.
///
/// [watchCreateAgentSubmit] gives the page its submit callback. The callback
/// posts `startBackgroundComposerFromSnapshot` through [cursorApiProvider]
/// once per tap; the page itself still never calls the network. Failures
/// become safe, user-facing text from [createAgentErrorMessage].
library;

import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:cursor_android/providers/cursor_api_providers.dart';
import 'package:cursor_android/providers/session_providers.dart';
import 'package:cursor_android/ui/create_agent_page.dart'
    show CreateAgentSubmit;
import 'package:cursor_android/ui/inbox_page.dart'
    show genericInboxError, safeInboxError;
import 'package:flutter/foundation.dart' show ValueChanged;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shown when the stored web session is missing or rejected.
const String createAgentReconnectError =
    'Your Cursor web session expired. Reconnect to start an agent.';

/// Safe New agent text for a failed start.
///
/// An HTTP 401 or a missing cookie asks the user to reconnect. Other
/// [ApiFailure]s show the status and the already sanitized code, and a
/// [CursorNetworkFailure] shows only the Dio error kind. Anything else, and
/// any text that still looks secret, becomes [genericInboxError].
String createAgentErrorMessage(Object error) {
  final String message = switch (error) {
    ApiFailure(status: 401) ||
    ApiFailure(code: 'connection_required') => createAgentReconnectError,
    ApiFailure(:final int status, :final String code) =>
      'Could not start the agent (HTTP $status · $code).',
    CursorNetworkFailure(:final String kind) =>
      'Could not reach Cursor ($kind). Check your connection.',
    _ => genericInboxError,
  };
  return safeInboxError(message);
}

/// The New agent submit callback, or null while no web session is stored.
///
/// The callback sends the form once with
/// `CursorApi.startBackgroundComposerFromSnapshot` and never retries it on
/// its own. It calls [onStarted] with the new `bcId` on success, or
/// [onFailed] with [createAgentErrorMessage] text on failure, so exception
/// text never reaches the UI.
CreateAgentSubmit? watchCreateAgentSubmit(
  WidgetRef ref, {
  required ValueChanged<String> onStarted,
  required ValueChanged<String> onFailed,
}) {
  if (!watchWebConnected(ref)) {
    return null;
  }
  return ({
    required String prompt,
    required List<String> repos,
    required String model,
    required String environment,
  }) async {
    final CursorApi api = ref.read(cursorApiProvider);
    final String bcId;
    try {
      bcId = await api.startBackgroundComposerFromSnapshot(
        prompt: prompt,
        repos: repos,
        model: model,
        environment: environment,
      );
    } on Object catch (error) {
      onFailed(createAgentErrorMessage(error));
      return;
    }
    onStarted(bcId);
  };
}
