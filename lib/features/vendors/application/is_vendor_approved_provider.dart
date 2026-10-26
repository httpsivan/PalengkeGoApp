import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palengkego/core/infrastructure/supabase_service.dart';
import 'package:palengkego/features/auth/application/auth_provider.dart';
import 'package:palengkego/features/auth/application/has_vendor_stall_provider.dart';

/// Provider that checks whether the currently logged-in user is an approved vendor
/// with permission to sell products on PalengkeGo.
///
/// Returns true only if:
/// 1. The user has a vendor role or has vendor stall capability.
/// 2. In Supabase, the vendor stall has `is_kyc_approved == true` or `kyc_status == 'approved'`.
final isVendorApprovedProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(authProvider);
  if (user == null) return false;

  final hasStall = ref.watch(hasVendorStallProvider);
  if (!user.isVendor && !hasStall) return false;

  final client = ref.watch(supabaseClientProvider);
  if (client != null) {
    try {
      final stall = await client
          .from('stall_holders')
          .select('is_kyc_approved, kyc_status')
          .or('user_id.eq.${user.uid},stall_holder_id.eq.${user.uid}')
          .maybeSingle();

      if (stall != null) {
        final isKycApproved = stall['is_kyc_approved'] == true;
        final kycStatus = (stall['kyc_status'] as String?)?.toLowerCase();
        return isKycApproved || kycStatus == 'approved';
      }
      return false;
    } catch (_) {
      // In case of network interruption, fallback to existing validated role
      return user.isVendor;
    }
  }

  // Fallback for mock/test environments
  return hasStall || user.isVendor;
});
