import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_display_criteria.dart';
import 'package:plezy/widgets/video_controls/widgets/quality_badge.dart';

void main() {
  test('resolution labels', () {
    expect(QualityBadge.resolutionLabel(3840, 2160), '4K');
    expect(QualityBadge.resolutionLabel(3840, 1600), '4K'); // scope crop
    expect(QualityBadge.resolutionLabel(1920, 1080), '1080p');
    expect(QualityBadge.resolutionLabel(1920, 800), '1080p');
    expect(QualityBadge.resolutionLabel(1280, 720), '720p');
    expect(QualityBadge.resolutionLabel(720, 576), 'SD');
    expect(QualityBadge.resolutionLabel(null, 1080), isNull);
  });

  test('dynamic range labels', () {
    expect(
      QualityBadge.labelsFor(const MediaDisplayCriteria(width: 3840, height: 2160, transfer: 'smpte2084')),
      ['4K', 'HDR10'],
    );
    expect(
      QualityBadge.labelsFor(
        const MediaDisplayCriteria(width: 3840, height: 2160, doviProfile: 8, doviCompatibilityId: 1),
      ),
      ['4K', 'DV'],
    );
    expect(QualityBadge.labelsFor(const MediaDisplayCriteria(width: 1920, height: 1080, transfer: 'bt709')), ['1080p']);
    expect(QualityBadge.labelsFor(null), isEmpty);
  });
}
