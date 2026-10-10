import 'package:flutter/material.dart';

import '../queue/search_queue.dart';
import 'results_screen.dart';
import 'store_accounts_screen.dart';
import 'store_status_chips.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.queue});

  final SearchQueue queue;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String text) {
    if (text.trim().isEmpty) return;
    widget.queue.add(text);
    _controller.clear();
  }

  void _open(SearchJob job) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultsScreen(queue: widget.queue, job: job)));

  @override
  Widget build(BuildContext context) {
    final queue = widget.queue;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sift Lord'),
        actions: [
          IconButton(
            tooltip: 'Store sign-ins',
            icon: const Icon(Icons.storefront_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => StoreAccountsScreen(queue: queue))),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: _submit,
              decoration: InputDecoration(
                hintText: 'Search Lazada and Shopee',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add_task),
                  tooltip: 'Queue search',
                  onPressed: () => _submit(_controller.text),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: queue,
              builder: (context, _) {
                final jobs = queue.jobs;
                if (jobs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Search for something. You can queue several searches and open each one while it finishes.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: jobs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final job = jobs[i];
                    return Dismissible(
                      key: ValueKey(job.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Theme.of(context).colorScheme.errorContainer,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Icon(Icons.delete_outline),
                      ),
                      onDismissed: (_) => queue.remove(job),
                      child: ListTile(
                        title: Text(job.query),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: StoreStatusChips(queue: queue, job: job, dense: true),
                        ),
                        trailing: job.isRunning
                            ? const SizedBox.square(
                                dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.chevron_right),
                        onTap: () => _open(job),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
