import 'package:flutter_test/flutter_test.dart';
import 'package:zmove_msg/data/models.dart';
import 'package:zmove_msg/services/batch_scheduler.dart';

void main() {
  group('BatchScheduler.nextSlot', () {
    test('soma o intervalo quando esta dentro da janela', () {
      final from = DateTime(2026, 11, 20, 10);
      final at = BatchScheduler.nextSlot(
        from: from,
        intervalMinutes: 10,
        windowStart: 8 * 60,
        windowEnd: 20 * 60,
      );
      expect(at, DateTime(2026, 11, 20, 10, 10));
    });

    test('antes da janela, pula para o inicio dela no mesmo dia', () {
      final from = DateTime(2026, 11, 20, 6);
      final at = BatchScheduler.nextSlot(
        from: from,
        intervalMinutes: 10,
        windowStart: 8 * 60,
        windowEnd: 20 * 60,
      );
      expect(at, DateTime(2026, 11, 20, 8));
    });

    test('depois da janela, pula para o inicio dela no dia seguinte', () {
      final from = DateTime(2026, 11, 20, 20, 30);
      final at = BatchScheduler.nextSlot(
        from: from,
        intervalMinutes: 10,
        windowStart: 8 * 60,
        windowEnd: 20 * 60,
      );
      expect(at, DateTime(2026, 11, 21, 8));
    });

    test('sem janela configurada, apenas soma o intervalo', () {
      final from = DateTime(2026, 11, 20, 23, 55);
      final at = BatchScheduler.nextSlot(
        from: from,
        intervalMinutes: 10,
        windowStart: 0,
        windowEnd: 0,
      );
      expect(at, DateTime(2026, 11, 21, 0, 5));
    });

    test('rotulo do intervalo', () {
      expect(BatchScheduler.intervalLabel(0), 'Desligado');
      expect(BatchScheduler.intervalLabel(5), '5 min');
      expect(BatchScheduler.intervalLabel(60), '1h');
      expect(BatchScheduler.intervalLabel(90), '1h 30min');
    });
  });

  group('Campaign', () {
    test('preserva anexos, intervalo e janela no mapa', () {
      const campaign = Campaign(
        name: 'Lote',
        media: [
          CampaignMedia(path: '/tmp/a.jpg', name: 'a.jpg'),
          CampaignMedia(path: '/tmp/b.pdf', name: 'b.pdf'),
        ],
        intervalMinutes: 10,
        windowStart: 9 * 60,
        windowEnd: 18 * 60,
      );

      final restored = Campaign.fromMap({...campaign.toMap(), 'id': 7});

      expect(restored.id, 7);
      expect(restored.name, 'Lote');
      expect(restored.media.length, 2);
      expect(restored.media.first.path, '/tmp/a.jpg');
      expect(restored.media.last.name, 'b.pdf');
      expect(restored.intervalMinutes, 10);
      expect(restored.windowStart, 540);
      expect(restored.windowEnd, 1080);
      expect(restored.batchEnabled, isTrue);
      expect(restored.hasMedia, isTrue);
    });

    test('le campanha antiga com um unico media_path', () {
      final restored = Campaign.fromMap({
        'id': 3,
        'name': 'Antiga',
        'template_id': null,
        'media_path': '/tmp/old.pdf',
        'media_name': 'old.pdf',
        'created_at': 0,
      });

      expect(restored.media.single.path, '/tmp/old.pdf');
      expect(restored.media.single.name, 'old.pdf');
      expect(restored.intervalMinutes, 0);
      expect(restored.windowStart, 8 * 60);
      expect(restored.windowEnd, 20 * 60);
      expect(restored.batchEnabled, isFalse);
    });
  });
}
