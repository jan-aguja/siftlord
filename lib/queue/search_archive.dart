import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'search_queue.dart';

/// Keeps the queue (searches, their last results and pins) in a JSON file on
/// the phone, so searches survive restarts. Writes are batched: the queue
/// notifies on every store update.
class SearchArchive {
  SearchArchive._(this._file);

  static Future<SearchArchive> open() async {
    final dir = await getApplicationSupportDirectory();
    return SearchArchive._(File('${dir.path}/searches.json'));
  }

  final File _file;
  SearchQueue? _queue;
  Timer? _debounce;

  /// Restores [queue] from the file, then keeps the file up to date.
  Future<void> attach(SearchQueue queue) async {
    _queue = queue;
    try {
      if (await _file.exists()) {
        queue.restore(jsonDecode(await _file.readAsString()) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('saved searches unreadable, starting fresh: $e');
    }
    queue.addListener(_schedule);
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), flush);
  }

  /// Writes now, e.g. when the app goes to the background.
  Future<void> flush() async {
    _debounce?.cancel();
    final q = _queue;
    if (q == null) return;
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(q.toJson()));
    await tmp.rename(_file.path);
  }
}
