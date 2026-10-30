import 'product.dart';

class CartItem {
  final Product product;
  int quantity;

  /// Kitchen instruction for this line ("less spicy"), printed on the KOT.
  String note;

  CartItem({required this.product, this.quantity = 1, this.note = ''});

  double get lineTotal => product.sellingPrice * quantity;
}
