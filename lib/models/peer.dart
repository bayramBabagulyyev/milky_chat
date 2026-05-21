class Peer {
  final String id;
  final String name;
  final String ip;
  final int port;
  DateTime lastSeen;
  bool isOnline;

  Peer({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    DateTime? lastSeen,
    this.isOnline = true,
  }) : lastSeen = lastSeen ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'port': port,
      };

  factory Peer.fromJson(Map<String, dynamic> json) => Peer(
        id: json['id'] as String,
        name: json['name'] as String,
        ip: json['ip'] as String,
        port: json['port'] as int,
      );

  @override
  bool operator ==(Object other) => other is Peer && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
