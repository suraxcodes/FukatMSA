class AdBlockConfig {
  final Set<String> domains;
  final Map<String, List<String>> selectors;

  AdBlockConfig({required this.domains, required this.selectors});

  factory AdBlockConfig.fromJson(Map<String, dynamic> json) {
    return AdBlockConfig(
      domains: Set<String>.from(json['domains'] as List),
      selectors: (json['selectors'] as Map).map((k, v) => MapEntry(
        k as String,
        List<String>.from(v as List),
      )),
    );
  }

  Map<String, dynamic> toJson() => {
        'domains': domains.toList(),
        'selectors': selectors,
      };
}
