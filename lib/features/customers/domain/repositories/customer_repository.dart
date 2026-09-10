import '../../../../core/utils/result.dart';
import '../models/customer.dart';

/// Read and write access to customer records.
abstract interface class CustomerRepository {
  /// Exact match on phone number, which is how the counter looks a customer up.
  Future<Result<Customer?>> findByPhone(String phone);

  Future<Result<Customer?>> findById(String id);

  /// Partial match on name or phone, for the search field.
  Future<Result<List<Customer>>> search(String query, {int limit});

  Future<Result<List<Customer>>> loadAll();

  Future<Result<void>> save(Customer customer);

  /// Returns the existing customer for [phone], or creates one.
  ///
  /// Exists as a single operation because the billing flow needs exactly this and
  /// doing it in two steps invites a duplicate record when the same number is
  /// entered twice in quick succession.
  Future<Result<Customer>> findOrCreateByPhone(String phone, {String? name});

  Future<Result<void>> delete(String id);
}
