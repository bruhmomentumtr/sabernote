import 'package:saber/components/settings/cloud_profile.dart';
import 'package:stow_codecs/stow_codecs.dart';

class QuotaCodec extends AbstractCodec<Quota, List> {
  const QuotaCodec();

  @override
  List<String> encode(Quota input) {
    return [input.used.toString(), input.total.toString()];
  }

  @override
  Quota decode(List<dynamic> encoded) {
    if (encoded.length != 2) {
      throw FormatException('Invalid quota format: $encoded');
    }
    final used = int.tryParse(encoded[0]) ?? 0;
    final total = int.tryParse(encoded[1]) ?? 0;
    return Quota(limit: total, usage: used, usageInDrive: used);
  }
}
