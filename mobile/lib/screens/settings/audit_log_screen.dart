import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  bool loading = true;
  String? error;
  List<dynamic> rows = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      final response = await DioClient.instance.dio.get('/audit');
      final data = response.data;
      if (data is Map && data['data'] is List) {
        rows = List<dynamic>.from(data['data'] as List);
      } else {
        rows = <dynamic>[];
      }
      error = null;
    } catch (e) {
      if (e is ApiException) {
        switch (e.type) {
          case ApiErrorType.notFound:
            error = 'Audit Log API is not available on the current server.';
            break;
          case ApiErrorType.unauthorized:
            error = 'Your session has expired. Please sign in again.';
            break;
          case ApiErrorType.forbidden:
            error = 'You do not have permission to view the audit log.';
            break;
          case ApiErrorType.timeout:
          case ApiErrorType.serverUnavailable:
            error = 'Backend is waking up or temporarily unavailable. Tap refresh after a moment.';
            break;
          case ApiErrorType.noInternet:
            error = 'No internet connection. Check the network and try again.';
            break;
          default:
            error = e.message;
        }
      } else {
        final message = e.toString();
        if (message.contains('404')) {
          error = 'Audit Log API is not available on the current server.';
        } else if (message.contains('401')) {
          error = 'Your session has expired. Please sign in again.';
        } else if (message.contains('403')) {
          error = 'You do not have permission to view the audit log.';
        } else {
          error = 'Could not load audit log: $e';
        }
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _actionLabel(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return 'Activity';
    return raw
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
        .join(' ');
  }

  String _details(dynamic value) {
    if (value is! Map || value.isEmpty) {
      return value?.toString() ?? '';
    }
    final parts = <String>[];
    value.forEach((key, item) {
      final label = key
          .toString()
          .replaceAll('_', ' ')
          .split(' ')
          .where((part) => part.isNotEmpty)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
          .join(' ');
      parts.add('$label: ${item?.toString() ?? '-'}');
    });
    return parts.join('  •  ');
  }

  String _timestamp(dynamic value) {
    if (value == null) return '';
    final date = DateTime.tryParse(value.toString())?.toLocal();
    if (date == null) return '';
    return DateFormat('dd MMM yyyy, hh:mm a').format(date);
  }

  Widget _auditRow(BuildContext context, dynamic item) {
    final map = item is Map ? item : <dynamic, dynamic>{};
    final actorValue = map['actor'];
    final actor = actorValue is Map
        ? (actorValue['name']?.toString() ?? 'System')
        : 'System';
    final role = actorValue is Map ? actorValue['role']?.toString() : null;
    final action = _actionLabel(map['action']);
    final entityType = map['entityType']?.toString() ?? '';
    final orderNumber = map['orderNumber'];
    final details = _details(map['details']);
    final timestamp = _timestamp(map['createdAt']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryLight,
            child: Icon(
              Icons.history_rounded,
              color: AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (actor.isNotEmpty) actor,
                    if (role != null && role.isNotEmpty) role,
                    if (entityType.isNotEmpty) entityType,
                    if (orderNumber != null) 'Order #$orderNumber',
                  ].join(' · '),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                if (timestamp.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    timestamp,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    details,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Log'),
        actions: [
          IconButton(
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded, color: AppColors.danger),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        error!,
                        style: TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
              ),
            if (loading) const LinearProgressIndicator(),
            if (!loading && error == null && rows.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: Text('No audit records found.')),
              ),
            ...rows.map((item) => _auditRow(context, item)),
          ],
        ),
      ),
    );
  }
}
