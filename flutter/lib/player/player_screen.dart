// STUB written by the app-shell branch so lib/ui compiles. The player developer's real file replaces this one at merge.
import 'package:flutter/material.dart';
import 'package:iptvmac/player/play_request.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key, required this.request, required this.host});

  final PlayRequest request;
  final PlayerHost host;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(request.title), actions: [IconButton(icon: const Icon(Icons.close), onPressed: host.closePlayer)]),
        body: Center(child: Text(request.url.toString())),
      );
}
