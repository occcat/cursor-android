/// Riverpod state for the stored display and refresh preferences.
///
/// [preferencesProvider] loads [Preferences] from [PreferencesStore] once
/// and writes every change back, so Settings choices survive a restart and
/// the Inbox usage capsule follows them.
library;

import 'package:cursor_android/data/preferences_store.dart';
import 'package:cursor_android/domain/preferences.dart';
import 'package:cursor_android/providers/session_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The [PreferencesStore] backed by [credentialsProvider].
final Provider<PreferencesStore> preferencesStoreProvider =
    Provider<PreferencesStore>(
      (Ref ref) => PreferencesStore(ref.watch(credentialsProvider)),
    );

/// Loads the stored preferences and saves changes.
///
/// A failed read resolves to the defaults instead of an error, so storage
/// contents quoted in an exception never reach the UI and the provider is
/// not retried.
class PreferencesNotifier extends AsyncNotifier<Preferences> {
  Future<void> _writes = Future<void>.value();

  @override
  Future<Preferences> build() async {
    final PreferencesStore store = ref.watch(preferencesStoreProvider);
    try {
      return await store.read();
    } on Object {
      return const Preferences();
    }
  }

  /// Shows [next] at once and writes it after any earlier write.
  ///
  /// Does nothing before the stored preferences have loaded, so a change
  /// made too early cannot overwrite them with defaults. When the write
  /// fails and nothing newer was chosen meanwhile, the previous preferences
  /// come back, so the screen keeps matching what is stored.
  Future<void> save(Preferences next) async {
    if (!state.hasValue) {
      return;
    }
    final Preferences previous = state.requireValue;
    final PreferencesStore store = ref.read(preferencesStoreProvider);
    state = AsyncData<Preferences>(next);
    final Future<void> write = _writes.then((void _) => store.write(next));
    _writes = write.catchError((Object _) {});
    try {
      await write;
    } on Object {
      if (ref.mounted &&
          state.hasValue &&
          identical(state.requireValue, next)) {
        state = AsyncData<Preferences>(previous);
      }
    }
  }
}

/// The stored preferences, defaults until the first read completes.
final AsyncNotifierProvider<PreferencesNotifier, Preferences>
preferencesProvider = AsyncNotifierProvider<PreferencesNotifier, Preferences>(
  PreferencesNotifier.new,
);

/// [preferencesProvider] as page inputs: the current preferences, the
/// defaults until they load, and whether they have loaded.
({Preferences preferences, bool loaded}) watchPreferences(WidgetRef ref) {
  final AsyncValue<Preferences> state = ref.watch(preferencesProvider);
  return state.hasValue
      ? (preferences: state.requireValue, loaded: true)
      : (preferences: const Preferences(), loaded: false);
}
