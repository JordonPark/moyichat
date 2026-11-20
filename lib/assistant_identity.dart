const defaultAssistantName = '모이챗';

const _name = r'''["“'‘]?([가-힣A-Za-z0-9][가-힣A-Za-z0-9 _.-]{0,23}?)["”'’]?''';
final _nameRequests = [
  RegExp(
    r'^(?:(?:앞으로|이제부터|이제)\s*)?(?:너의?|네)\s*이름(?:은|이|을)\s*(?:이제\s*)?' +
        _name +
        r'\s*(?:이야|야|이에요|예요|(?:으)?로\s*바꿔\s*줘|(?:이)?라고\s*할게)[.!]?$',
  ),
  RegExp(
    r'^(?:(?:앞으로|이제부터)\s*)?(?:너를|널)\s*' + _name + r'\s*(?:이라고|라고)\s*부를게[.!]?$',
  ),
];

String? requestedAssistantName(String message) {
  for (final pattern in _nameRequests) {
    final match = pattern.firstMatch(message.trim());
    if (match != null) return match.group(1)!.trim();
  }
  return null;
}
