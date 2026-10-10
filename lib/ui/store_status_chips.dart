import 'package:flutter/material.dart';

import '../queue/search_queue.dart';
import '../stores/store_runner.dart';
import 'store_style.dart';
import 'store_web_screen.dart';

int _attentionRank(StoreStatus s) => switch (s) {
      StoreStatus.needsLogin || StoreStatus.needsVerification || StoreStatus.failed => 0,
      StoreStatus.queued || StoreStatus.running => 1,
      StoreStatus.done => 2,
    };

/// Stores needing the user first (sign in, check, failed), then those still
/// searching, then finished ones, so incomplete results are obvious.
List<MapEntry<String, StoreProgress>> attentionFirst(SearchJob job) {
  final entries = job.progress.entries.toList();
  // List.sort isn't stable; break ties by the original store order.
  final order = {for (final (i, e) in entries.indexed) e.key: i};
  entries.sort((a, b) {
    final r = _attentionRank(a.value.status).compareTo(_attentionRank(b.value.status));
    return r != 0 ? r : order[a.key]!.compareTo(order[b.key]!);
  });
  return entries;
}

/// One compact chip per store on a single line (scrolls sideways): result
/// count, or what's blocking it. Tapping a blocked chip opens the store so
/// the user can sign in or clear the check, then retries.
///
/// With [onToggle], finished stores' chips also filter: tapping one hides or
/// shows that store's results; [hidden] holds the hidden store ids.
class StoreStatusChips extends StatelessWidget {
  const StoreStatusChips({
    super.key,
    required this.queue,
    required this.job,
    this.hidden = const {},
    this.onToggle,
  });

  final SearchQueue queue;
  final SearchJob job;
  final Set<String> hidden;
  final void Function(String storeId)? onToggle;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final MapEntry(key: id, value: p) in attentionFirst(job))
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _chip(context, id, p),
            ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String id, StoreProgress p) {
    final store = queue.store(id);
    final blocked = p.status == StoreStatus.needsLogin ||
        p.status == StoreStatus.needsVerification ||
        p.status == StoreStatus.failed;
    final label = Text(p.status == StoreStatus.done
        ? '${store.name} ${p.items.length}'
        : '${store.name} · ${statusLabel(p.status, p.items.length)}');
    final avatar = Icon(statusIcon(p.status), size: 16, color: storeColor(id));
    const density = VisualDensity.compact;

    if (p.status == StoreStatus.done && onToggle != null) {
      final shown = !hidden.contains(id);
      return FilterChip(
        avatar: shown
            ? CircleAvatar(radius: 5, backgroundColor: storeColor(id))
            : Icon(Icons.visibility_off_outlined, size: 16, color: storeColor(id)),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        labelPadding: const EdgeInsets.only(left: 2, right: 6),
        label: label,
        selected: shown,
        visualDensity: density,
        tooltip: shown ? 'Hide ${store.name} results' : 'Show ${store.name} results',
        onSelected: (_) => onToggle!(id),
      );
    }
    if (!blocked) return Chip(avatar: avatar, label: label, visualDensity: density);
    return ActionChip(
      avatar: avatar,
      label: label,
      visualDensity: density,
      tooltip: p.detail,
      onPressed: () async {
        if (p.status != StoreStatus.failed) {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => StoreWebScreen(
              title: p.status == StoreStatus.needsLogin
                  ? 'Sign in to ${store.name}'
                  : '${store.name} check',
              url: p.status == StoreStatus.needsLogin
                  ? store.loginUrl
                  : store.searchUrl(job.query),
              hint: p.status == StoreStatus.needsLogin ? store.signInHint : null,
            ),
          ));
        }
        queue.retryBlocked(id);
      },
    );
  }
}

/// The queue list's one-line version: "✓ Lazada 40 · ✓ Shopee 20 · ⟳ Marketplace".
/// Read-only; the results screen's chips are where blocked stores get fixed.
class StoreStatusSummary extends StatelessWidget {
  const StoreStatusSummary({super.key, required this.queue, required this.job});

  final SearchQueue queue;
  final SearchJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spans = <InlineSpan>[];
    for (final MapEntry(key: id, value: p) in attentionFirst(job)) {
      if (spans.isNotEmpty) spans.add(const TextSpan(text: '  ·  '));
      final blocked = p.status == StoreStatus.needsLogin ||
          p.status == StoreStatus.needsVerification ||
          p.status == StoreStatus.failed;
      spans
        ..add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(statusIcon(p.status), size: 14, color: storeColor(id)),
          ),
        ))
        ..add(TextSpan(
          text: p.status == StoreStatus.done
              ? '${queue.store(id).name} ${p.items.length}'
              : '${queue.store(id).name} ${statusLabel(p.status, p.items.length)}',
          style: blocked ? TextStyle(color: theme.colorScheme.error) : null,
        ));
    }
    return Text.rich(TextSpan(children: spans), style: theme.textTheme.bodySmall);
  }
}
