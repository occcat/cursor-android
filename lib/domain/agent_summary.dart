/// Agent list model and local Inbox filtering, ported from Kotlin 0.1.5
/// `Inbox` in `CursorApp.kt` and the JSON helpers in `CursorRepository.kt`.
library;

/// One background agent row from `background-composer/list`.
class AgentSummary {
  const AgentSummary({
    this.bcId = '',
    this.name = '',
    this.status = '',
    this.updatedAtMs,
    this.updatedAtLabel = '',
  });

  /// Reads one `composers` entry. Missing or non-scalar fields become `''`,
  /// like Kotlin's `JsonObject.string`.
  factory AgentSummary.fromJson(Map<Object?, Object?> json) {
    return AgentSummary(
      bcId: _string(json['bcId']),
      name: _string(json['name']),
      status: _string(json['status']),
      updatedAtMs: _millis(json['updatedAtMs']),
      updatedAtLabel: _string(json['updatedAt']),
    );
  }

  final String bcId;
  final String name;

  /// API status string, shown verbatim, for example `RUNNING`.
  final String status;

  /// Last update in epoch milliseconds, when the API sent a whole number.
  final int? updatedAtMs;

  /// The API's `updatedAt` text, used when [updatedAtMs] is missing.
  final String updatedAtLabel;
}

/// Agents from a list response's `composers` array; anything else is empty.
List<AgentSummary> agentsFromComposers(Map<Object?, Object?>? agentsRoot) {
  final Object? composers = agentsRoot?['composers'];
  if (composers is! List) {
    return const <AgentSummary>[];
  }
  return <AgentSummary>[
    for (final Map<Object?, Object?> entry
        in composers.whereType<Map<Object?, Object?>>())
      AgentSummary.fromJson(entry),
  ];
}

/// Agents whose name contains [query] (ignoring case), hiding `ARCHIVED`
/// agents unless [includeArchived].
List<AgentSummary> filterAgents(
  List<AgentSummary> agents, {
  required String query,
  required bool includeArchived,
}) {
  final String needle = query.toLowerCase();
  return <AgentSummary>[
    for (final AgentSummary agent in agents)
      if ((includeArchived || agent.status != 'ARCHIVED') &&
          agent.name.toLowerCase().contains(needle))
        agent,
  ];
}

final RegExp _wholeNumber = RegExp(r'^[+-]?[0-9]+$');

/// Text of a JSON scalar, or `''`.
String _string(Object? value) =>
    value is String ? value : (value is num || value is bool ? '$value' : '');

/// Whole-number milliseconds from an int or a decimal-digit string, like
/// Kotlin's `toLongOrNull` on the primitive's text.
int? _millis(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is String && _wholeNumber.hasMatch(value)) {
    return int.tryParse(value);
  }
  return null;
}
