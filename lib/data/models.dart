import 'dart:convert';

/// Status de consentimento do contato para receber mensagens.
enum OptIn {
  unknown,
  optedIn,
  optedOut;

  String get db => switch (this) {
    OptIn.unknown => 'unknown',
    OptIn.optedIn => 'opted_in',
    OptIn.optedOut => 'opted_out',
  };

  String get label => switch (this) {
    OptIn.unknown => 'Sem status',
    OptIn.optedIn => 'Autorizado',
    OptIn.optedOut => 'Descadastrado',
  };

  static OptIn fromDb(String? value) => switch (value) {
    'opted_in' => OptIn.optedIn,
    'opted_out' => OptIn.optedOut,
    _ => OptIn.unknown,
  };
}

class Contact {
  const Contact({
    this.id,
    required this.name,
    required this.phone,
    this.group,
    this.optIn = OptIn.unknown,
    this.notes,
    this.lastSentAt,
    this.createdAt,
  });

  final int? id;
  final String name;

  /// Somente digitos, incluindo o DDI (ex.: 5511912345678).
  final String phone;
  final String? group;
  final OptIn optIn;
  final String? notes;
  final DateTime? lastSentAt;
  final DateTime? createdAt;

  Contact copyWith({
    int? id,
    String? name,
    String? phone,
    String? group,
    bool clearGroup = false,
    OptIn? optIn,
    String? notes,
    bool clearNotes = false,
    DateTime? lastSentAt,
    DateTime? createdAt,
  }) {
    return Contact(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      group: clearGroup ? null : (group ?? this.group),
      optIn: optIn ?? this.optIn,
      notes: clearNotes ? null : (notes ?? this.notes),
      lastSentAt: lastSentAt ?? this.lastSentAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static Contact fromMap(Map<String, Object?> map) => Contact(
    id: map['id'] as int?,
    name: (map['name'] as String?) ?? '',
    phone: (map['phone'] as String?) ?? '',
    group: map['group_name'] as String?,
    optIn: OptIn.fromDb(map['opt_in'] as String?),
    notes: map['notes'] as String?,
    lastSentAt: _toDate(map['last_sent_at']),
    createdAt: _toDate(map['created_at']),
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'phone': phone,
    'group_name': group,
    'opt_in': optIn.db,
    'notes': notes,
    'last_sent_at': lastSentAt?.millisecondsSinceEpoch,
    'created_at': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
  };
}

class MessageTemplate {
  const MessageTemplate({
    this.id,
    required this.name,
    required this.body,
    this.updatedAt,
  });

  final int? id;
  final String name;
  final String body;
  final DateTime? updatedAt;

  MessageTemplate copyWith({
    int? id,
    String? name,
    String? body,
    DateTime? updatedAt,
  }) => MessageTemplate(
    id: id ?? this.id,
    name: name ?? this.name,
    body: body ?? this.body,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  static MessageTemplate fromMap(Map<String, Object?> map) => MessageTemplate(
    id: map['id'] as int?,
    name: (map['name'] as String?) ?? '',
    body: (map['body'] as String?) ?? '',
    updatedAt: _toDate(map['updated_at']),
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'body': body,
    'updated_at': (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
  };
}

/// Arquivo (imagem ou PDF) anexado a uma campanha.
class CampaignMedia {
  const CampaignMedia({required this.path, required this.name});

  /// Caminho local do arquivo salvo dentro do app.
  final String path;

  /// Nome original, usado na interface.
  final String name;

  Map<String, Object?> toJson() => {'path': path, 'name': name};

  static CampaignMedia? fromJson(Object? value) {
    if (value is Map) {
      final path = value['path'];
      if (path is String && path.isNotEmpty) {
        return CampaignMedia(
          path: path,
          name: (value['name'] as String?) ?? 'Anexo',
        );
      }
    }
    return null;
  }
}

class Campaign {
  const Campaign({
    this.id,
    required this.name,
    this.templateId,
    this.media = const <CampaignMedia>[],
    this.intervalMinutes = 0,
    this.windowStart = 8 * 60,
    this.windowEnd = 20 * 60,
    this.createdAt,
  });

  final int? id;
  final String name;
  final int? templateId;
  final List<CampaignMedia> media;

  /// Intervalo entre um contato e o proximo, em minutos. 0 = sem intervalo
  /// (o modo continuo abre o proximo assim que voce volta do WhatsApp).
  final int intervalMinutes;

  /// Janela de horario permitida para os lembretes, em minutos desde 0h.
  /// Quando start == end, nao ha restricao de horario.
  final int windowStart;
  final int windowEnd;
  final DateTime? createdAt;

  bool get hasMedia => media.isNotEmpty;
  String? get mediaPath => media.isEmpty ? null : media.first.path;
  String? get mediaName => media.isEmpty ? null : media.first.name;
  bool get batchEnabled => intervalMinutes > 0;

  Campaign copyWith({
    int? id,
    String? name,
    int? templateId,
    List<CampaignMedia>? media,
    int? intervalMinutes,
    int? windowStart,
    int? windowEnd,
    DateTime? createdAt,
  }) => Campaign(
    id: id ?? this.id,
    name: name ?? this.name,
    templateId: templateId ?? this.templateId,
    media: media ?? this.media,
    intervalMinutes: intervalMinutes ?? this.intervalMinutes,
    windowStart: windowStart ?? this.windowStart,
    windowEnd: windowEnd ?? this.windowEnd,
    createdAt: createdAt ?? this.createdAt,
  );

  static Campaign fromMap(Map<String, Object?> map) {
    final parsed = <CampaignMedia>[];
    final rawMedia = map['media_items'];
    if (rawMedia is String && rawMedia.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawMedia);
        if (decoded is List) {
          for (final item in decoded) {
            final media = CampaignMedia.fromJson(item);
            if (media != null) parsed.add(media);
          }
        }
      } catch (_) {
        // Registro antigo ou corrompido: cai para as colunas antigas.
      }
    }
    if (parsed.isEmpty) {
      final legacyPath = map['media_path'] as String?;
      if (legacyPath != null && legacyPath.isNotEmpty) {
        parsed.add(
          CampaignMedia(
            path: legacyPath,
            name: (map['media_name'] as String?) ?? 'Anexo',
          ),
        );
      }
    }

    return Campaign(
      id: map['id'] as int?,
      name: (map['name'] as String?) ?? '',
      templateId: map['template_id'] as int?,
      media: parsed,
      intervalMinutes: (map['interval_minutes'] as num?)?.toInt() ?? 0,
      windowStart: (map['window_start'] as num?)?.toInt() ?? 8 * 60,
      windowEnd: (map['window_end'] as num?)?.toInt() ?? 20 * 60,
      createdAt: _toDate(map['created_at']),
    );
  }

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'template_id': templateId,
    'media_path': mediaPath,
    'media_name': mediaName,
    'media_items': media.isEmpty
        ? null
        : jsonEncode(media.map((item) => item.toJson()).toList()),
    'interval_minutes': intervalMinutes,
    'window_start': windowStart,
    'window_end': windowEnd,
    'created_at': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
  };
}

enum SendStatus {
  pending,
  sent,
  skipped,
  failed;

  String get db => name;

  String get label => switch (this) {
    SendStatus.pending => 'Pendente',
    SendStatus.sent => 'Enviado',
    SendStatus.skipped => 'Pulado',
    SendStatus.failed => 'Falhou',
  };

  static SendStatus fromDb(String? value) {
    for (final s in SendStatus.values) {
      if (s.name == value) return s;
    }
    return SendStatus.pending;
  }
}

class CampaignItem {
  const CampaignItem({
    this.id,
    required this.campaignId,
    required this.contactId,
    required this.renderedText,
    this.status = SendStatus.pending,
    this.sentAt,
  });

  final int? id;
  final int campaignId;
  final int contactId;
  final String renderedText;
  final SendStatus status;
  final DateTime? sentAt;

  static CampaignItem fromMap(Map<String, Object?> map) => CampaignItem(
    id: map['id'] as int?,
    campaignId: (map['campaign_id'] as int?) ?? 0,
    contactId: (map['contact_id'] as int?) ?? 0,
    renderedText: (map['rendered_text'] as String?) ?? '',
    status: SendStatus.fromDb(map['status'] as String?),
    sentAt: _toDate(map['sent_at']),
  );
}

/// Item da fila com o contato ja carregado.
class QueueEntry {
  const QueueEntry({required this.item, required this.contact});

  final CampaignItem item;
  final Contact contact;
}

class CampaignStats {
  const CampaignStats({
    required this.total,
    required this.sent,
    required this.skipped,
    required this.pending,
  });

  final int total;
  final int sent;
  final int skipped;
  final int pending;

  bool get isFinished => pending == 0 && total > 0;

  double get progress => total == 0 ? 0 : (sent + skipped) / total;
}

class ScheduleItem {
  const ScheduleItem({
    this.id,
    required this.title,
    required this.campaignId,
    required this.at,
    this.done = false,
  });

  final int? id;
  final String title;
  final int campaignId;
  final DateTime at;
  final bool done;

  ScheduleItem copyWith({
    int? id,
    String? title,
    int? campaignId,
    DateTime? at,
    bool? done,
  }) => ScheduleItem(
    id: id ?? this.id,
    title: title ?? this.title,
    campaignId: campaignId ?? this.campaignId,
    at: at ?? this.at,
    done: done ?? this.done,
  );

  static ScheduleItem fromMap(Map<String, Object?> map) => ScheduleItem(
    id: map['id'] as int?,
    title: (map['title'] as String?) ?? '',
    campaignId: (map['campaign_id'] as int?) ?? 0,
    at: _toDate(map['at']) ?? DateTime.now(),
    done: (map['done'] as int? ?? 0) == 1,
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'title': title,
    'campaign_id': campaignId,
    'at': at.millisecondsSinceEpoch,
    'done': done ? 1 : 0,
  };
}

class AppSettings {
  const AppSettings({
    this.senderName = '',
    this.companyName = '',
    this.defaultDdi = '55',
    this.dailyLimit = 50,
  });

  final String senderName;
  final String companyName;
  final String defaultDdi;
  final int dailyLimit;

  AppSettings copyWith({
    String? senderName,
    String? companyName,
    String? defaultDdi,
    int? dailyLimit,
  }) => AppSettings(
    senderName: senderName ?? this.senderName,
    companyName: companyName ?? this.companyName,
    defaultDdi: defaultDdi ?? this.defaultDdi,
    dailyLimit: dailyLimit ?? this.dailyLimit,
  );

  Map<String, String> toMap() => {
    'senderName': senderName,
    'companyName': companyName,
    'defaultDdi': defaultDdi,
    'dailyLimit': dailyLimit.toString(),
  };

  static AppSettings fromMap(Map<String, String> map) => AppSettings(
    senderName: map['senderName'] ?? '',
    companyName: map['companyName'] ?? '',
    defaultDdi: map['defaultDdi'] ?? '55',
    dailyLimit: int.tryParse(map['dailyLimit'] ?? '') ?? 50,
  );
}

DateTime? _toDate(Object? value) {
  if (value == null) return null;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// Codifica/decodifica um backup simples em JSON.
class BackupCodec {
  static String encode(List<Contact> contacts) =>
      const JsonEncoder.withIndent('  ').convert({
        'app': 'zmove_msg',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'contacts': contacts
            .map(
              (c) => {
                'name': c.name,
                'phone': c.phone,
                'group': c.group,
                'optIn': c.optIn.db,
                'notes': c.notes,
              },
            )
            .toList(),
      });
}
