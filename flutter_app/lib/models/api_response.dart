class ApiResponse<T> {
  final int code;
  final String message;
  final T? data;
  final String? requestId;

  ApiResponse({
    required this.code,
    required this.message,
    this.data,
    this.requestId,
  });

  bool get isSuccess => code == 0;

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic json)? fromJsonT,
  ) {
    return ApiResponse<T>(
      code: json['code'] as int? ?? -1,
      message: json['message'] as String? ?? '',
      data: json['data'] != null && fromJsonT != null ? fromJsonT(json['data']) : json['data'] as T?,
      requestId: json['request_id'] as String?,
    );
  }
}
