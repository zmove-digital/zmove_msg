import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/template_renderer.dart';
import '../data/app_database.dart';
import '../data/models.dart';

class DuplicatePhoneException implements Exception {
  const DuplicatePhoneException(this.phone);

  final String phone;

  @override
  String toString() => 'Telefone já cadastrado: $phone';
}

class ImportResult {
  const ImportResult({
    this.added = 0,
    this.updated = 0,
    this.duplicated = 0,
    this.invalid = 0,
  });

  final int added;
  final int updated;
  final int duplicated;

  /// Linhas ignoradas (sem nome ou telefone invalido).
  final int invalid;

  int get total => added + updated;
}

/// Estado central do app. Mantem tudo em memoria (base local pequena) e
/// notifica a interface a cada alteracao.
class AppState extends ChangeNotifier {
  AppState(this._database);

  final AppDatabase _database;

  bool ready = false;
  List<Contact> contacts = [];
  List<MessageTemplate> templates = [];
  List<Campaign> campaigns = [];
  List<ScheduleItem> schedules = [];
  Map<int, CampaignStats> campaignStats = {};
  AppSettings settings = const AppSettings();

  int sentToday = 0;
  int sentTotal = 0;

  // ---------------------------------------------------------------- inicializacao

  Future<void> init() async {
    final db = await _database.database;
    await _seedTemplates(db);
    await _loadSettings(db);
    await refresh();
    ready = true;
    notifyListeners();
  }

  Future<void> refresh() async {
    final db = await _database.database;
    final rows = await Future.wait([
      db.query('contacts', orderBy: 'name COLLATE NOCASE ASC'),
      db.query('templates', orderBy: 'updated_at DESC'),
      db.query('campaigns', orderBy: 'created_at DESC'),
      db.query('schedules', orderBy: 'at ASC'),
    ]);

    contacts = rows[0].map(Contact.fromMap).toList();
    templates = rows[1].map(MessageTemplate.fromMap).toList();
    campaigns = rows[2].map(Campaign.fromMap).toList();
    schedules = rows[3].map(ScheduleItem.fromMap).toList();

    await _reloadCounters(db);
    notifyListeners();
  }

  Future<void> _reloadCounters(Database db) async {
    final statRows = await db.rawQuery('''
      SELECT campaign_id,
             COUNT(*) AS total,
             SUM(CASE WHEN status = 'sent' THEN 1 ELSE 0 END) AS sent,
             SUM(CASE WHEN status = 'skipped' THEN 1 ELSE 0 END) AS skipped
      FROM campaign_items
      GROUP BY campaign_id
    ''');
    final map = <int, CampaignStats>{};
    for (final row in statRows) {
      final total = (row['total'] as num?)?.toInt() ?? 0;
      final sent = (row['sent'] as num?)?.toInt() ?? 0;
      final skipped = (row['skipped'] as num?)?.toInt() ?? 0;
      map[(row['campaign_id'] as num).toInt()] = CampaignStats(
        total: total,
        sent: sent,
        skipped: skipped,
        pending: total - sent - skipped,
      );
    }
    campaignStats = map;

    final startOfDay = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    ).millisecondsSinceEpoch;

    final todayRow = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM campaign_items "
      "WHERE status = 'sent' AND sent_at >= ?",
      [startOfDay],
    );
    sentToday = (todayRow.first['c'] as num?)?.toInt() ?? 0;

    final totalRow = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM campaign_items WHERE status = 'sent'",
    );
    sentTotal = (totalRow.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> _seedTemplates(Database db) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM templates'),
    );
    if ((count ?? 0) > 0) return;

    const seeds = [
      MessageTemplate(
        name: 'Aviso rápido',
        body:
            '{{saudacao}}, {{primeiro_nome}}! Tudo bem?\n\n'
            'Passando para avisar que seu pedido está pronto. '
            'Pode retirar no horário de sempre.\n\n'
            'Qualquer dúvida é só responder aqui.\n\n'
            '{{remetente}}',
      ),
      MessageTemplate(
        name: 'Cobrança amigável',
        body:
            'Olá, {{primeiro_nome}}! {{saudacao}}.\n\n'
            'Passando para lembrar do valor referente ao seu pedido, '
            'com vencimento em {{data}}.\n\n'
            'Se já pagou, pode desconsiderar esta mensagem. '
            'Qualquer coisa, estou à disposição.\n\n'
            '{{remetente}} - {{empresa}}',
      ),
      MessageTemplate(
        name: 'Promoção',
        body:
            '{{saudacao}}, {{primeiro_nome}}! 🎉\n\n'
            'Temos uma novidade especial para você esta semana. '
            'Aproveite as condições exclusivas enquanto durar o estoque!\n\n'
            'Quer saber mais? Responda esta mensagem.\n\n'
            '{{empresa}}',
      ),
    ];

    final now = DateTime.now();
    final batch = db.batch();
    for (final t in seeds) {
      batch.insert('templates', t.copyWith(updatedAt: now).toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<void> _loadSettings(Database db) async {
    final rows = await db.query('settings');
    final map = <String, String>{
      for (final row in rows)
        (row['key'] as String): (row['value'] as String? ?? ''),
    };
    settings = AppSettings.fromMap(map);
  }

  Future<void> saveSettings(AppSettings next) async {
    final db = await _database.database;
    final batch = db.batch();
    next.toMap().forEach((key, value) {
      batch.insert('settings', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await batch.commit(noResult: true);
    settings = next;
    notifyListeners();
  }

  // -------------------------------------------------------------------- contatos

  Contact? contactById(int id) {
    for (final c in contacts) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<int> saveContact(Contact contact) async {
    final db = await _database.database;
    try {
      int id;
      if (contact.id == null) {
        id = await db.insert(
          'contacts',
          contact.copyWith(createdAt: DateTime.now()).toMap(),
        );
      } else {
        id = contact.id!;
        await db.update(
          'contacts',
          contact.toMap(),
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      await refresh();
      return id;
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw DuplicatePhoneException(contact.phone);
      }
      rethrow;
    }
  }

  Future<void> deleteContact(int id) async {
    final db = await _database.database;
    await db.delete('contacts', where: 'id = ?', whereArgs: [id]);
    await refresh();
  }

  Future<void> setOptIn(int id, OptIn optIn) async {
    final db = await _database.database;
    await db.update(
      'contacts',
      {'opt_in': optIn.db},
      where: 'id = ?',
      whereArgs: [id],
    );
    await refresh();
  }

  Future<ImportResult> importContacts(List<Contact> incoming) async {
    final db = await _database.database;
    var added = 0;
    var updated = 0;
    var invalid = 0;

    await db.transaction((txn) async {
      for (final contact in incoming) {
        if (contact.name.trim().isEmpty || contact.phone.length < 12) {
          invalid++;
          continue;
        }
        final existing = await txn.query(
          'contacts',
          columns: ['id'],
          where: 'phone = ?',
          whereArgs: [contact.phone],
          limit: 1,
        );
        if (existing.isEmpty) {
          await txn.insert('contacts', contact.toMap());
          added++;
        } else {
          final id = existing.first['id'] as int;
          final patch = <String, Object?>{
            'name': contact.name,
            'group_name': contact.group,
            'opt_in': contact.optIn.db,
          };
          await txn.update('contacts', patch, where: 'id = ?', whereArgs: [id]);
          updated++;
        }
      }
    });

    await refresh();
    return ImportResult(added: added, updated: updated, invalid: invalid);
  }

  // ------------------------------------------------------------------- templates

  Future<void> saveTemplate(MessageTemplate template) async {
    final db = await _database.database;
    final value = template.copyWith(updatedAt: DateTime.now()).toMap();
    if (template.id == null) {
      await db.insert('templates', value);
    } else {
      await db.update(
        'templates',
        value,
        where: 'id = ?',
        whereArgs: [template.id],
      );
    }
    await refresh();
  }

  Future<void> deleteTemplate(int id) async {
    final db = await _database.database;
    await db.delete('templates', where: 'id = ?', whereArgs: [id]);
    await refresh();
  }

  // ------------------------------------------------------------------- campanhas

  Campaign? campaignById(int id) {
    for (final c in campaigns) {
      if (c.id == id) return c;
    }
    return null;
  }

  CampaignStats? statsFor(int campaignId) => campaignStats[campaignId];

  Future<int> createCampaign({
    required String name,
    required MessageTemplate template,
    required List<Contact> selected,
    String? mediaPath,
    String? mediaName,
  }) async {
    final db = await _database.database;
    final now = DateTime.now();
    final campaignId = await db.insert(
      'campaigns',
      Campaign(
        name: name,
        templateId: template.id,
        mediaPath: mediaPath,
        mediaName: mediaName,
        createdAt: now,
      ).toMap(),
    );

    final batch = db.batch();
    for (final contact in selected) {
      batch.insert('campaign_items', {
        'campaign_id': campaignId,
        'contact_id': contact.id,
        'rendered_text': TemplateRenderer.render(
          template.body,
          contact,
          settings,
          now: now,
        ),
        'status': SendStatus.pending.db,
      });
    }
    await batch.commit(noResult: true);
    await refresh();
    return campaignId;
  }

  Future<List<QueueEntry>> entriesFor(int campaignId) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
      SELECT i.id AS i_id, i.campaign_id AS i_campaign, i.contact_id AS i_contact,
             i.rendered_text AS i_text, i.status AS i_status, i.sent_at AS i_sent,
             c.name AS c_name, c.phone AS c_phone, c.group_name AS c_group,
             c.opt_in AS c_opt_in, c.notes AS c_notes,
             c.last_sent_at AS c_last, c.created_at AS c_created
      FROM campaign_items i
      INNER JOIN contacts c ON c.id = i.contact_id
      WHERE i.campaign_id = ?
      ORDER BY i.id ASC
    ''',
      [campaignId],
    );

    return rows.map((row) {
      final contact = Contact(
        id: row['i_contact'] as int?,
        name: row['c_name'] as String? ?? '',
        phone: row['c_phone'] as String? ?? '',
        group: row['c_group'] as String?,
        optIn: OptIn.fromDb(row['c_opt_in'] as String?),
        notes: row['c_notes'] as String?,
        lastSentAt: _date(row['c_last']),
        createdAt: _date(row['c_created']),
      );
      return QueueEntry(
        item: CampaignItem(
          id: row['i_id'] as int?,
          campaignId: (row['i_campaign'] as num).toInt(),
          contactId: (row['i_contact'] as num).toInt(),
          renderedText: row['i_text'] as String? ?? '',
          status: SendStatus.fromDb(row['i_status'] as String?),
          sentAt: _date(row['i_sent']),
        ),
        contact: contact,
      );
    }).toList();
  }

  Future<void> setItemStatus(CampaignItem item, SendStatus status) async {
    final db = await _database.database;
    final now = DateTime.now();
    await db.update(
      'campaign_items',
      {
        'status': status.db,
        'sent_at': status == SendStatus.sent
            ? now.millisecondsSinceEpoch
            : null,
      },
      where: 'id = ?',
      whereArgs: [item.id],
    );
    if (status == SendStatus.sent) {
      await db.update(
        'contacts',
        {'last_sent_at': now.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [item.contactId],
      );
    } else {
      // Ao desfazer/pular, o ultimo envio volta a ser o item enviado mais
      // recente que restou para este contato.
      await _recomputeLastSent(db, item.contactId);
    }
    await _reloadCounters(db);
    notifyListeners();
  }

  Future<void> _recomputeLastSent(Database db, int contactId) async {
    final row = await db.rawQuery(
      "SELECT MAX(sent_at) AS last FROM campaign_items "
      "WHERE contact_id = ? AND status = 'sent'",
      [contactId],
    );
    await db.update(
      'contacts',
      {'last_sent_at': row.first['last'] as int?},
      where: 'id = ?',
      whereArgs: [contactId],
    );
  }

  Future<void> deleteCampaign(int id) async {
    final db = await _database.database;
    final affected = await db.query(
      'campaign_items',
      columns: ['contact_id'],
      where: 'campaign_id = ?',
      whereArgs: [id],
    );
    final contactIds = {for (final row in affected) row['contact_id'] as int};
    await db.delete('campaigns', where: 'id = ?', whereArgs: [id]);
    await db.delete('schedules', where: 'campaign_id = ?', whereArgs: [id]);
    for (final contactId in contactIds) {
      await _recomputeLastSent(db, contactId);
    }
    await refresh();
  }

  // ------------------------------------------------------------------ agendamentos

  Future<int> addSchedule({
    required String title,
    required int campaignId,
    required DateTime at,
  }) async {
    final db = await _database.database;
    final id = await db.insert(
      'schedules',
      ScheduleItem(title: title, campaignId: campaignId, at: at).toMap(),
    );
    await refresh();
    return id;
  }

  Future<void> deleteSchedule(int id) async {
    final db = await _database.database;
    await db.delete('schedules', where: 'id = ?', whereArgs: [id]);
    await refresh();
  }
}

DateTime? _date(Object? value) {
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}
