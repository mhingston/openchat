class PromptTemplate {
  const PromptTemplate({
    required this.id,
    required this.name,
    required this.systemPrompt,
    required this.createdAt,
    required this.updatedAt,
    this.model,
    this.temperature,
  });

  factory PromptTemplate.fromJson(Map<String, dynamic> json) {
    return PromptTemplate(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      model: json['model'] as String?,
      temperature: (json['temperature'] as num?)?.toDouble(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String id;
  final String name;
  final String systemPrompt;
  final String? model;
  final double? temperature;
  final DateTime createdAt;
  final DateTime updatedAt;

  PromptTemplate copyWith({
    String? id,
    String? name,
    String? systemPrompt,
    String? model,
    double? temperature,
    bool clearModel = false,
    bool clearTemperature = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PromptTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      model: clearModel ? null : (model ?? this.model),
      temperature: clearTemperature ? null : (temperature ?? this.temperature),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'systemPrompt': systemPrompt,
      if (model != null) 'model': model,
      if (temperature != null) 'temperature': temperature,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
