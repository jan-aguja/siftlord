import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/item.dart';
import '../stores/store_adapter.dart';
import '../stores/store_runner.dart';

class StoreProgress {
  StoreStatus status = StoreStatus.queued;
  List<Item> items = const [];
  String? detail;
}

/// One search, fanned out to every store. Results fill in per store as each
/// finishes, so a job can be opened while it's still running.
class SearchJob {
  SearchJob(this.id, this.query, List<StoreAdapter> stores)
      : createdAt = DateTime.now(),
        progress = {for (final s in stores) s.id: StoreProgress()};

  final int id;
  final String query;
  final DateTime createdAt;
  final Map<String, StoreProgress> progress;

  bool get isRunning => progress.values.any(
      (p) => p.status == StoreStatus.queued || p.status == StoreStatus.running);

  List<Item> get items => [for (final p in progress.values) ...p.items];
}

/// The job list. Jobs run oldest-first, [maxConcurrentJobs] at a time; within a
/// job all stores run in parallel.
class SearchQueue extends ChangeNotifier {
  SearchQueue(this.stores, {this.runner = const StoreRunner(), this.maxConcurrentJobs = 2});

  final List<StoreAdapter> stores;
  final StoreRunner runner;
  final int maxConcurrentJobs;

  final List<SearchJob> _jobs = [];
  final List<(SearchJob, StoreAdapter)> _pending = [];
  final Set<int> _activeJobs = {};
  int _nextId = 1;

  /// Newest first.
  List<SearchJob> get jobs => List.unmodifiable(_jobs.reversed);

  StoreAdapter store(String id) => stores.firstWhere((s) => s.id == id);

  SearchJob add(String query) {
    final job = SearchJob(_nextId++, query.trim(), stores);
    _jobs.add(job);
    for (final s in stores) {
      _pending.add((job, s));
    }
    notifyListeners();
    _pump();
    return job;
  }

  void remove(SearchJob job) {
    _jobs.remove(job);
    _pending.removeWhere((p) => p.$1 == job);
    _activeJobs.remove(job.id);
    notifyListeners();
    _pump();
  }

  /// Re-runs one store for a job, e.g. after the user signed in.
  void retry(SearchJob job, String storeId) {
    final p = job.progress[storeId];
    if (p == null || p.status == StoreStatus.running) return;
    p
      ..status = StoreStatus.queued
      ..items = const []
      ..detail = null;
    _pending.add((job, store(storeId)));
    notifyListeners();
    _pump();
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
    p
      ..status = r.status
      ..items = r.items
      ..detail = r.detail;
    if (r.detail != null) debugPrint('[${store.id}] "${job.query}": ${r.status} ${r.detail}');
    if (!job.isRunning || !_jobs.contains(job)) _activeJobs.remove(job.id);
    notifyListeners();
    _pump();
  }
}
