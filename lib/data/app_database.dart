import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// Acesso ao banco local (SQLite). Tudo fica no aparelho, sem servidor.
class AppDatabase {
  Database? _db;

  Future<Database> get database async {
    return _db ??= await _open();
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, 'zmove_msg.db'),
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        final batch = db.batch();
        batch.execute('''
          CREATE TABLE contacts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT NOT NULL UNIQUE,
            group_name TEXT,
            opt_in TEXT NOT NULL DEFAULT 'unknown',
            notes TEXT,
            last_sent_at INTEGER,
            created_at INTEGER NOT NULL
          )
        ''');
        batch.execute('''
          CREATE TABLE templates (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            body TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        batch.execute('''
          CREATE TABLE campaigns (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            template_id INTEGER,
            media_path TEXT,
            media_name TEXT,
            created_at INTEGER NOT NULL
          )
        ''');
        batch.execute('''
          CREATE TABLE campaign_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            campaign_id INTEGER NOT NULL,
            contact_id INTEGER NOT NULL,
            rendered_text TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            sent_at INTEGER,
            FOREIGN KEY (campaign_id) REFERENCES campaigns (id) ON DELETE CASCADE,
            FOREIGN KEY (contact_id) REFERENCES contacts (id) ON DELETE CASCADE
          )
        ''');
        batch.execute(
          'CREATE INDEX idx_items_campaign ON campaign_items (campaign_id)',
        );
        batch.execute('''
          CREATE TABLE schedules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            campaign_id INTEGER NOT NULL,
            at INTEGER NOT NULL,
            done INTEGER NOT NULL DEFAULT 0
          )
        ''');
        batch.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await batch.commit(noResult: true);
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
