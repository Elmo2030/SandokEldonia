// Phase 0 spike (flutter/PLAN.md): does libmpv (media_kit) play a stream on Android, and does the SQLite that ships with the app have FTS5 with
// unicode61 diacritics removal and fast prefix search? Results go to the screen and to logcat (lines starting with SPIKE_).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

const streamUrl = String.fromEnvironment('SPIKE_URL', defaultValue: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MaterialApp(home: Spike()));
}

class Spike extends StatefulWidget {
  const Spike({super.key});
  @override
  State<Spike> createState() => _SpikeState();
}

class _SpikeState extends State<Spike> {
  final player = Player();
  late final controller = VideoController(player);
  final lines = <String>[];

  void log(String s) {
    debugPrint('SPIKE_$s');
    if (mounted) setState(() => lines.add(s));
  }

  @override
  void initState() {
    super.initState();
    _fts();
    player.stream.error.listen((e) => log('PLAYER error=$e'));
    player.stream.width.listen((w) => log('PLAYER width=$w'));
    player.stream.playing.listen((p) => log('PLAYER playing=$p'));
    Timer.periodic(const Duration(seconds: 3), (_) => debugPrint('SPIKE_PLAYER pos=${player.state.position.inSeconds}s dur=${player.state.duration.inSeconds}s'));
    player.open(Media(streamUrl));
  }

  void _fts() {
    final db = sql.sqlite3.openInMemory();
    log('FTS sqlite=${sql.sqlite3.version}');
    try {
      db.execute("CREATE VIRTUAL TABLE fts USING fts5(name, tokenize='unicode61 remove_diacritics 2')");
      final names = ['Café del Mar', 'Crème brûlée TV', 'חדשות הנמל 24', 'שָׁלוֹם עולם', 'قناة الأخبار', 'الجَزيرة مباشر', 'Harbor News 24', 'Aurora Sports 1'];
      for (final n in names) {
        db.execute('INSERT INTO fts(name) VALUES (?)', [n]);
      }
      String q(String w) => db.select('SELECT name FROM fts WHERE fts MATCH ? ORDER BY rank', ['"$w"*']).map((r) => r['name']).join(' | ');
      log('FTS cafe -> ${q('cafe')}');
      log('FTS creme -> ${q('creme')}');
      log('FTS שלום (no niqqud) -> ${q('שלום')}');
      log('FTS חדשות -> ${q('חדשות')}');
      log('FTS الجزيرة (no tashkeel) -> ${q('الجزيرة')}');
      log('FTS harb -> ${q('harb')}');
      // speed: 100k rows, prefix query (the Swift app answers in under 250 ms)
      db.execute('BEGIN');
      final st = db.prepare('INSERT INTO fts(name) VALUES (?)');
      final sw = Stopwatch()..start();
      for (var i = 0; i < 100000; i++) {
        st.execute(['Channel $i Sports ${i % 97} News ${i % 13} ערוץ ${i % 31}']);
      }
      st.close();
      db.execute('COMMIT');
      log('FTS insert100k=${sw.elapsedMilliseconds}ms');
      sw
        ..reset()
        ..start();
      final n = db.select("SELECT rowid FROM fts WHERE fts MATCH ? ORDER BY rank LIMIT 5000", ['"spor"* "new"*']).length;
      log('FTS prefix query rows=$n in ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      log('FTS FAILED $e');
    }
    db.close();
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Column(children: [
            AspectRatio(aspectRatio: 16 / 9, child: Video(controller: controller)),
            Expanded(child: ListView(children: [for (final l in lines) Text(l, style: const TextStyle(fontSize: 12))])),
          ]),
        ),
      );
}
