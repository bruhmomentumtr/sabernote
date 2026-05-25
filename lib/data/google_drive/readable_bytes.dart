/// 🤖 Generated wholely or partially with GPT-5 Codex; OpenAI
library;

String readableBytes(num? bytes) {
  if (bytes == null) return '... B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

  var i = 0;
  var groupedBytes = bytes.toDouble();
  while (groupedBytes >= 1024 && i < units.length - 1) {
    groupedBytes /= 1024;
    i++;
  }
  if (groupedBytes > 900 && i < units.length - 1) {
    groupedBytes /= 1024;
    i++;
  }

  final int decimalPlaces;
  if (i == 0) {
    decimalPlaces = 0;
  } else if (groupedBytes < 10) {
    decimalPlaces = 2;
  } else if (groupedBytes < 100) {
    decimalPlaces = 1;
  } else {
    decimalPlaces = 0;
  }

  return '${groupedBytes.toStringAsFixed(decimalPlaces)} ${units[i]}';
}
