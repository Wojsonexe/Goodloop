import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goodloop/core/update/update_service.dart';

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());
