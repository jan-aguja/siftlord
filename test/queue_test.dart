import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:siftlord/models/item.dart';
import 'package:siftlord/queue/search_queue.dart';
import 'package:siftlord/stores/facebook.dart';
import 'package:siftlord/stores/lazada.dart';
import 'package:siftlord/stores/shopee.dart';
import 'package:siftlord/stores/store_adapter.dart';
import 'package:siftlord/stores/store_runner.dart';
import 'package:siftlord/stores/store_settings.dart';

/// Answers each store with a preset status and items, when told to.
class FakeRunner extends StoreRunner {
  FakeRunner(this.statuses, {this.items = const {}});

  final Map<String, StoreStatus> statuses;
  Map<String, List<Item>> items;
  final gate = Completer<void>();

  @override
  Future<StoreRunResult> run(StoreAdapter store, String query) async {
    await gate.future;
    final status = statuses[store.id] ?? StoreStatus.done;
    return StoreRunResult(status, status == StoreStatus.done ? items[store.id] ?? const [] : const []);
  }
}

Item item(String store, String id, double price, {String? title}) => Item(
      storeId: store,
      title: title ?? 'Thing $id',
      price: price,
      url: Uri.parse('https://$store.example/$id'),
      rank: 0,
    );

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('health: busy while searching, then attention if a store needs the user', () async {
    final runner = FakeRunner({'lazada': StoreStatus.done, 'shopee': StoreStatus.needsLogin});
    final queue = SearchQueue([LazadaAdapter(), ShopeeAdapter()], runner: runner);
    final job = queue.add('airpods');
    await settle();
    expect(job.health, JobHealth.busy);
    runner.gate.complete();
    await settle();
    expect(job.health, JobHealth.attention);
  });

  test('health: done when every store fetched', () async {
    final runner = FakeRunner({})..gate.complete();
    final queue = SearchQueue([LazadaAdapter(), ShopeeAdapter()], runner: runner);
    final job = queue.add('airpods');
    await settle();
    expect(job.health, JobHealth.done);
  });

  test('saved searches list first and survive remove and clear', () async {
    final runner = FakeRunner({})..gate.complete();
    final queue = SearchQueue([LazadaAdapter()], runner: runner);

    final a = queue.add('a');
    final b = queue.add('b');
    queue.add('c');
    expect(queue.jobs.map((j) => j.query), ['c', 'b', 'a']);

    queue.setSaved(a, true);
    expect(queue.jobs.map((j) => j.query), ['a', 'c', 'b']);

    expect(queue.remove(a), isFalse);
    expect(queue.jobs, hasLength(3));
    expect(queue.remove(b), isTrue);
    expect(queue.jobs.map((j) => j.query), ['a', 'c']);

    expect(queue.clearUnsaved(), 1);
    expect(queue.jobs.map((j) => j.query), ['a']);

    queue.setSaved(a, false);
    expect(queue.remove(a), isTrue);
  });

  test('cleanup removes only unhearted searches not refreshed in time', () async {
    final runner = FakeRunner({})..gate.complete();
    final queue = SearchQueue([LazadaAdapter()], runner: runner);
    final old = queue.add('old');
    final kept = queue.add('old but hearted')..saved = true;
    queue.add('new');
    await settle();
    old.updatedAt = DateTime.now().subtract(const Duration(days: 10));
    kept.updatedAt = old.updatedAt;
    expect(queue.removeOlderThan(const Duration(days: 7)), 1);
    expect(queue.jobs.map((j) => j.query), ['old but hearted', 'new']);
  });

  test('refresh keeps old results on failure and updates pins', () async {
    final runner = FakeRunner({}, items: {
      'lazada': [item('lazada', '1', 100), item('lazada', '2', 200)],
    })
      ..gate.complete();
    final queue = SearchQueue([LazadaAdapter(), ShopeeAdapter()], runner: runner);
    final job = queue.add('thing');
    await settle();
    expect(job.items, hasLength(2));

    // The first pin hearts the search.
    expect(queue.togglePin(job, job.items[1]), isTrue);
    expect(job.saved, isTrue);
    expect(job.pins.single.pinnedPrice, 200);

    // Unhearted later: further pins don't heart it again.
    queue.setSaved(job, false);
    expect(queue.togglePin(job, job.items[0]), isFalse);
    expect(job.saved, isFalse);
    queue.togglePin(job, job.items[0]);

    runner.items = {'lazada': [item('lazada', '2', 150)]};
    runner.statuses['shopee'] = StoreStatus.failed;
    queue.refresh(job);
    await settle();
    expect(job.pins.single.item.price, 150);
    expect(job.pins.single.missing, isFalse);

    runner.items = {'lazada': [item('lazada', '3', 90)]};
    queue.refresh(job);
    await settle();
    expect(job.pins.single.missing, isTrue);
    expect(job.pins.single.item.price, 150, reason: 'keeps the last copy seen');

    runner.statuses['lazada'] = StoreStatus.failed;
    queue.refresh(job);
    await settle();
    expect(job.progress['lazada']!.items.single.price, 90, reason: 'failed refresh keeps results');
  });

  test('round-trips through JSON and re-runs stores cut off mid-search', () async {
    final runner = FakeRunner({}, items: {
      'lazada': [item('lazada', '1', 100)],
    })
      ..gate.complete();
    final queue = SearchQueue([LazadaAdapter(), ShopeeAdapter()], runner: runner);
    final job = queue.add('thing');
    await settle();
    queue.togglePin(job, job.items.single);
    job.progress['shopee']!.status = StoreStatus.running;
    final json = jsonDecode(jsonEncode(queue.toJson())) as Map<String, dynamic>;

    final restored = SearchQueue([LazadaAdapter(), ShopeeAdapter()], runner: runner)..restore(json);
    final j = restored.jobs.single;
    expect(j.query, 'thing');
    expect(j.saved, isTrue);
    expect(j.pins.single.item.key, 'https://lazada.example/1');
    expect(j.progress['lazada']!.items.single.price, 100);
    await settle();
    expect(j.progress['shopee']!.status, StoreStatus.done);
    expect(restored.add('next').id, greaterThan(j.id));
  });

  test('stores turned on most recently list first', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await StoreSettings.load([LazadaAdapter(), ShopeeAdapter(), FacebookMarketplaceAdapter()]);
    expect(settings.orderedStores.map((s) => s.id), ['lazada', 'shopee', 'facebook']);
    settings.setEnabled('facebook', true);
    expect(settings.orderedStores.map((s) => s.id), ['facebook', 'lazada', 'shopee']);
    settings.setEnabled('lazada', false);
    expect(settings.orderedStores.map((s) => s.id), ['facebook', 'shopee', 'lazada']);
    expect(settings.enabledStores.map((s) => s.id), ['facebook', 'shopee']);
  });
}
