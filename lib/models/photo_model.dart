class PhotoModel {
  final String id;
  final String path;
  final String name;
  final DateTime createdAt;
  final bool isEdited;
  final int? width;
  final int? height;

  const PhotoModel({
    required this.id,
    required this.path,
    required this.name,
    required this.createdAt,
    this.isEdited = false,
    this.width,
    this.height,
  });

  PhotoModel copyWith({
    String? id,
    String? path,
    String? name,
    DateTime? createdAt,
    bool? isEdited,
    int? width,
    int? height,
  }) {
    return PhotoModel(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      isEdited: isEdited ?? this.isEdited,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}
