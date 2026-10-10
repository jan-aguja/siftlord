import 'package:flutter/material.dart';

import '../queue/search_queue.dart';
import 'store_style.dart';
import 'store_web_screen.dart';

class StoreAccountsScreen extends StatelessWidget {
  const StoreAccountsScreen({super.key, required this.queue});

  final SearchQueue queue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Store sign-ins')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'Searches run on this phone, as you. Some stores only show results when you\'re '
              'signed in. You sign in on the store\'s own page, and Sift Lord never sees your password.',
            ),
          ),
          for (final store in queue.stores.where((s) => s.allowSignIn))
            ListTile(
              leading: CircleAvatar(
                backgroundColor: storeColor(store.id),
                child: Text(store.name[0], style: const TextStyle(color: Colors.white)),
              ),
              title: Text(store.name),
              subtitle: Text(store.id == 'shopee' ? 'Sign-in required to search' : 'Works without signing in'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StoreWebScreen(title: store.name, url: store.loginUrl, hint: store.signInHint),
                ));
                queue.retryBlocked(store.id);
              },
            ),
        ],
      ),
    );
  }
}
