import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/item.dart';
import '../stores/store_adapter.dart';
import '../stores/store_runner.dart';

class StoreProgress {
  StoreStatus status = StoreStatus.queued;
  List<Item> items = const [];
  String? detail;

  Map<String, Object?> toJson() => {
        'status': status.name,
        if (detail != null) 'detail': detail,
        'items': [for (final i in items) i.toJson()],
      };

  static StoreProgress fromJson(Map<String, dynamic> j) => StoreProgress()
    ..status = StoreStatus.values.asNameMap()[j['status']] ?? StoreStatus.failed
    ..detail = j['detail'] as String?
    ..items = [for (final i in j['items'] as List? ?? const []) Item.fromJson(i as Map<String, dynamic>)];
}

/// A listing the user pinned in a search's results. Keeps the last copy seen,
/// so it stays (marked) even when a refresh no longer finds it.
class Pin {
  Pin(this.item, {DateTime? pinnedAt, double? pinnedPrice, this.missing = false})
      : pinnedAt = pinnedAt ?? DateTime.now(),
        pinnedPrice = pinnedPrice ?? item.price;

  Item item;
  final DateTime pinnedAt;

  /// The price when pinned, to show how it moved since.
  final double pinnedPrice;

  /// The last finished search on its store didn't return it.
  bool missing;

  Map<String, Object?> toJson() => {
        'item': item.toJson(),
        'pinnedAt': pinnedAt.toIso8601String(),
        'pinnedPrice': pinnedPrice,
        if (missing) 'missing': true,
      };

  static Pin fromJson(Map<String, dynamic> j) => Pin(
        Item.fromJson(j['item'] as Map<String, dynamic>),
        pinnedAt: DateTime.tryParse('${j['pinnedAt']}'),
        pinnedPrice: (j['pinnedPrice'] as num?)?.toDouble(),
        missing: j['missing'] == true,
      );
}

/// How a job is doing overall, for the queue's status indicator.
enum JobHealth {
  /// Every store fetched.
  done,

  /// Still searching.
  busy,

  /// A store needs the user: sign in, a check, or it failed.
  attention,
}

/// One search, fanned out to every store. Results fill in per store as each
/// finishes, so a job can be opened while it's still running.
class SearchJob {
  SearchJob(this.id, this.query, List<StoreAdapter> stores)
      : createdAt = DateTime.now(),
        updatedAt = DateTime.now(),
        progress = {for (final s in stores) s.id: StoreProgress()};

  SearchJob._restored(this.id, this.query, this.createdAt, this.updatedAt, this.progress);

  final int id;
  final String query;
  final DateTime createdAt;

  /// When a store last finished for this search (or when it was queued).
  DateTime updatedAt;
  final Map<String, StoreProgress> progress;

  /// Hearted: protected from swipe-to-delete, clear-all and auto-cleanup.
  bool saved = false;

  /// Pinned listings, newest first.
  final List<Pin> pins = [];

  /// The first pin hearts the search once; after that, unhearting sticks.
  bool pinHearted = false;

  JobHealth get health {
    final s = progress.values.map((p) => p.status);
    if (s.any((x) => x == StoreStatus.needsLogin || x == StoreStatus.needsVerification ||
        x == StoreStatus.failed)) {
      return JobHealth.attention;
    }
    return isRunning ? JobHealth.busy : JobHealth.done;
  }

  bool get isRunning => progress.values.any(
      (p) => p.status == StoreStatus.queued || p.status == StoreStatus.running);

  List<Item> get items => [for (final p in progress.values) ...p.items];

  Pin? pinFor(Item item) {
    for (final p in pins) {
      if (p.item.key == item.key) return p;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'query': query,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (saved) 'saved': true,
        if (pinHearted) 'pinHearted': true,
        'stores': {for (final e in progress.entries) e.key: e.value.toJson()},
        if (pins.isNotEmpty) 'pins': [for (final p in pins) p.toJson()],
      };

  /// Stores no longer in [storeIds] are dropped.
  static SearchJob fromJson(Map<String, dynamic> j, Set<String> storeIds) {
    final created = DateTime.tryParse('${j['createdAt']}') ?? DateTime.now();
    final job = SearchJob._restored(
      j['id'] as int,
      j['query'] as String,
      created,
      DateTime.tryParse('${j['updatedAt']}') ?? created,
      {
        for (final e in (j['stores'] as Map<String, dynamic>? ?? const {}).entries)
          if (storeIds.contains(e.key)) e.key: StoreProgress.fromJson(e.value as Map<String, dynamic>),
      },
    )
      ..saved = j['saved'] == true
      ..pinHearted = j['pinHearted'] == true;
    job.pins.addAll([
      for (final p in j['pins'] as List? ?? const [])
        if (storeIds.contains((p as Map<String, dynamic>)['item']?['store'])) Pin.fromJson(p),
    ]);
    return job;
  }
}

/// The job list. Jobs run oldest-first, [maxConcurrentJobs] at a time; within a
/// job all stores run in parallel.
class SearchQueue extends ChangeNotifier {
  SearchQueue(this.stores, {this.runner = const StoreRunner(), this.maxConcurrentJobs = 2});

  final List<StoreAdapter> stores;
  final StoreRunner runner;
  final int maxConcurrentJobs;

  /// Called whenever a store finishes for a job.
  void Function(SearchJob job)? onStoreFinished;

  final List<SearchJob> _jobs = [];
  final List<(SearchJob, StoreAdapter)> _pending = [];
  final Set<int> _activeJobs = {};
  int _nextId = 1;

  /// Saved searches first, then the rest; newest first within each.
  List<SearchJob> get jobs => List.unmodifiable([
        ..._jobs.reversed.where((j) => j.saved),
        ..._jobs.reversed.where((j) => !j.saved),
      ]);

  StoreAdapter store(String id) => stores.firstWhere((s) => s.id == id);

  /// Queues a search on [only] (default: every store).
  SearchJob add(String query, {List<StoreAdapter>? only, bool saved = false}) {
    final targets = only ?? stores;
    final job = SearchJob(_nextId++, query.trim(), targets)..saved = saved;
    _jobs.add(job);
    for (final s in targets) {
      _pending.add((job, s));
    }
    notifyListeners();
    _pump();
    return job;
  }

  void setSaved(SearchJob job, bool saved) {
    if (job.saved == saved) return;
    job.saved = saved;
    notifyListeners();
  }

  /// Pins or unpins [item] in [job]. The first pin a search ever gets also
  /// hearts it, so the pin isn't lost to a cleanup; returns true when it did.
  bool togglePin(SearchJob job, Item item) {
    final existing = job.pinFor(item);
    var hearted = false;
    if (existing != null) {
      job.pins.remove(existing);
    } else {
      job.pins.insert(0, Pin(item));
      if (!job.saved && !job.pinHearted) {
        job.saved = true;
        hearted = true;
      }
      job.pinHearted = true;
    }
    notifyListeners();
    return hearted;
  }

  /// Removes an unsaved job. Saved ones must be un-hearted first; returns
  /// whether it was removed.
  bool remove(SearchJob job) {
    if (job.saved) return false;
    _drop(job);
    notifyListeners();
    _pump();
    return true;
  }

  /// Removes every unhearted search; returns how many went.
  int clearUnsaved() => _removeWhere((j) => !j.saved);

  /// Removes unhearted searches not updated within [age]; returns how many went.
  int removeOlderThan(Duration age, {DateTime? now}) {
    final cutoff = (now ?? DateTime.now()).subtract(age);
    return _removeWhere((j) => !j.saved && !j.isRunning && j.updatedAt.isBefore(cutoff));
  }

  int _removeWhere(bool Function(SearchJob) test) {
    final gone = _jobs.where(test).toList();
    if (gone.isEmpty) return 0;
    gone.forEach(_drop);
    notifyListeners();
    _pump();
    return gone.length;
  }

  void _drop(SearchJob job) {
    _jobs.remove(job);
    _pending.removeWhere((p) => p.$1 == job);
    _activeJobs.remove(job.id);
  }

  /// Re-runs one store for a job, e.g. after the user signed in. Old results
  /// stay visible until the new ones arrive.
  void retry(SearchJob job, String storeId) {
    if (!_jobs.contains(job)) return;
    final p = job.progress.putIfAbsent(storeId, StoreProgress.new);
    if (p.status == StoreStatus.running ||
        _pending.any((e) => e.$1 == job && e.$2.id == storeId)) {
      return;
    }
    p
      ..status = StoreStatus.queued
      ..detail = null;
    _pending.add((job, store(storeId)));
    notifyListeners();
    _pump();
  }

  /// Searches again for fresh prices, on the job's stores plus [also] (stores
  /// turned on since).
  void refresh(SearchJob job, {List<StoreAdapter> also = const []}) {
    for (final id in {...job.progress.keys, for (final s in also) s.id}) {
      retry(job, id);
    }
  }

  /// Retries every job where this store asked for sign-in or a check.
  void retryBlocked(String storeId) {
    for (final job in _jobs) {
      final s = job.progress[storeId]?.status;
      if (s == StoreStatus.needsLogin || s == StoreStatus.needsVerification ||
          s == StoreStatus.failed) {
        retry(job, storeId);
      }
    }
  }

  Map<String, Object?> toJson() => {
        'version': 1,
        'jobs': [for (final j in _jobs) j.toJson()],
      };

  /// Brings back searches saved by [toJson]. Stores that were mid-search
  /// when the app closed are searched again.
  void restore(Map<String, dynamic> json) {
    final ids = {for (final s in stores) s.id};
    for (final j in json['jobs'] as List? ?? const []) {
      try {
        final job = SearchJob.fromJson(j as Map<String, dynamic>, ids);
        if (job.progress.isEmpty) continue;
        _jobs.add(job);
        if (job.id >= _nextId) _nextId = job.id + 1;
        for (final e in job.progress.entries) {
          if (e.value.status == StoreStatus.queued || e.value.status == StoreStatus.running) {
            e.value.status = StoreStatus.queued;
            _pending.add((job, store(e.key)));
          }
        }
      } catch (e) {
        debugPrint('skipping unreadable saved search: $e');
      }
    }
    notifyListeners();
    _pump();
  }

  void _pump() {
    for (final (job, store) in List.of(_pending)) {
      final canStart = _activeJobs.contains(job.id) || _activeJobs.length < maxConcurrentJobs;
      if (!canStart) continue;
      _pending.remove((job, store));
      _activeJobs.add(job.id);
      unawaited(_run(job, store));
    }
  }

  Future<void> _run(SearchJob job, StoreAdapter store) async {
    final p = job.progress[store.id]!..status = StoreStatus.running;
    notifyListeners();
    final r = await runner.run(store, job.query);
    // A failed refresh keeps the results it had rather than blanking them.
    p
      ..status = r.status
      ..items = r.status == StoreStatus.done || p.items.isEmpty ? r.items : p.items
      ..detail = r.detail;
    if (r.status == StoreStatus.done) {
      job.updatedAt = DateTime.now();
      _refreshPins(job, store.id, r.items);
    }
    if (r.detail != null) debugPrint('[${store.id}] "${job.query}": ${r.status} ${r.detail}');
    if (!job.isRunning || !_jobs.contains(job)) _activeJobs.remove(job.id);
    onStoreFinished?.call(job);
    notifyListeners();
    _pump();
  }

  /// Pins take the store's latest copy of their listing, or are marked missing.
  void _refreshPins(SearchJob job, String storeId, List<Item> fresh) {
    final byKey = {for (final i in fresh) i.key: i};
    for (final pin in job.pins) {
      if (pin.item.storeId != storeId) continue;
      final now = byKey[pin.item.key];
      pin.missing = now == null;
      if (now != null) pin.item = now;
    }
  }
}
