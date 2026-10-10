import 'package:flutter/material.dart';

import '../queue/search_queue.dart';
import '../stores/store_runner.dart';
import 'store_style.dart';
import 'store_web_screen.dart';

/// One chip per store: result count, or what's blocking it. Tapping a blocked
/// chip opens the store so the user can sign in or clear the check, then
/// retries.
class StoreStatusChips extends StatelessWidget {
  const StoreStatusChips({super.key, required this.queue, required this.job, this.dense = false});

  final SearchQueue queue;
  final SearchJob job;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final MapEntry(key: id, value: p) in job.progress.entries)
          _chip(context, id, p),
      ],
    );
  }

  Widget _chip(BuildContext context, String id, StoreProgress p) {
    final store = queue.store(id);
    final blocked = p.status == StoreStatus.needsLogin ||
        p.status == StoreStatus.needsVerification ||
        p.status == StoreStatus.failed;
    final label = Text('${store.name} · ${statusLabel(p.status, p.items.length)}');
    final avatar = Icon(statusIcon(p.status), size: 16, color: storeColor(id));
    final density = dense ? VisualDensity.compact : null;
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
            ),
          ));
        }
        queue.retryBlocked(id);
      },
    );
  }
}
