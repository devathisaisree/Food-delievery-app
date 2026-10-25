// THE FEED - hyperlocal, zero-commission food ordering app (Flutter mini-project)
//
// Accounts : Sign up / Login for Customer and Restaurant Owner (role is fixed
//            per account, login is remembered so the app opens directly)
// Customer : Home (festival offers slider, specials, deals), Menu, Cart (saved
//            in the database), Orders, Profile
// Owner    : Dishes CRUD (price, discount, photo from gallery or icon), Orders
//            management, Profile
// Database : SQLite via sqflite  ->  Create, Read, Update, Delete

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:flutter/foundation.dart';
void main() {
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }

  runApp(const TheFeedApp());
}

// ---------------------------------------------------------------------------
// CONSTANTS + GLOBALS
// ---------------------------------------------------------------------------
const kOrange = Color(0xFFFF512F);
const kPink = Color(0xFFDD2476);

const diets = ['Veg', 'Non-Veg', 'Jain'];
const categories = [
  'Biryani',
  'Meals',
  'Snacks',
  'Starters',
  'Pizza & Burgers',
  'Desserts',
  'Drinks',
];
const categoryEmoji = {
  'Biryani': '🍛',
  'Meals': '🍱',
  'Snacks': '🥞',
  'Starters': '🧀',
  'Pizza & Burgers': '🍕',
  'Desserts': '🍮',
  'Drinks': '🥤',
};
const emojis = [
  '🍛', '🍗', '🍖', '🍚', '🍱', '🥞', '🧀', '🍔', '🍕', '🍮',
  '🍨', '🥭', '☕', '🥘', '🥪', '🍜', '🌮', '🥗', '🍩', '🥤',
];
const statuses = [
  'Pending',
  'Preparing',
  'Out for delivery',
  'Delivered',
  'Cancelled',
];
const slots = [
  'As soon as possible',
  '12:00 PM',
  '1:00 PM',
  '2:00 PM',
  '7:00 PM',
  '8:00 PM',
  '9:00 PM',
];
const palettes = [
  [Color(0xFFFFE0B2), Color(0xFFFFAB91)],
  [Color(0xFFC8E6C9), Color(0xFF81C784)],
  [Color(0xFFBBDEFB), Color(0xFF90CAF9)],
  [Color(0xFFF8BBD0), Color(0xFFF48FB1)],
  [Color(0xFFFFF9C4), Color(0xFFFFE082)],
  [Color(0xFFE1BEE7), Color(0xFFCE93D8)],
];

String rs(num n) => '₹${n.toStringAsFixed(0)}';

/// Price after discount.
double eff(Map<String, dynamic> m) =>
    ((m['price'] as num) * (100 - (m['discount'] as num)) / 100).roundToDouble();

Color statusColor(String s) {
  switch (s) {
    case 'Delivered':
      return Colors.green;
    case 'Cancelled':
      return Colors.red;
    case 'Out for delivery':
      return Colors.blue;
    case 'Preparing':
      return Colors.orange;
    default:
      return Colors.grey;
  }
}

InputDecoration deco(String label, [IconData? icon]) => InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon),
      border: const OutlineInputBorder(),
    );

/// The logged-in user (row from the users table).
Map<String, dynamic> me = {};

// ---------------------------------------------------------------------------
// DATABASE LAYER
// ---------------------------------------------------------------------------
class DB {
  static Database? _db;

  static Future<Database> get db async {
  if (_db != null) return _db!;

  if (kIsWeb) {
    _db = await openDatabase(
      'the_feed_web.db',
      version: 1,
      onCreate: (d, v) => _create(d),
    );
  } else {
    final path = p.join(
      await getDatabasesPath(),
      'the_feed_v2.db',
    );

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (d, v) => _create(d),
    );
  }

  return _db!;
}

  static Future<void> _create(Database d) async {
    await d.execute('''CREATE TABLE users(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      role TEXT, name TEXT, email TEXT UNIQUE, phone TEXT,
      password TEXT, address TEXT, restaurant TEXT)''');
    await d.execute('CREATE TABLE session(user_id INTEGER)');
    await d.execute('''CREATE TABLE menu(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      owner_id INTEGER, name TEXT, price REAL, category TEXT, diet TEXT,
      stock INTEGER, is_special INTEGER, sold_out INTEGER,
      emoji TEXT, image TEXT, rating REAL, discount INTEGER)''');
    await d.execute('''CREATE TABLE cart(
      user_id INTEGER, dish_id INTEGER, qty INTEGER,
      PRIMARY KEY(user_id, dish_id))''');
    await d.execute('''CREATE TABLE orders(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER, owner_id INTEGER, restaurant TEXT,
      customer TEXT, phone TEXT, address TEXT, item TEXT, qty INTEGER,
      total REAL, slot TEXT, status TEXT)''');

    // demo accounts
    await d.insert('users', {
      'role': 'owner',
      'name': 'Ravi Kumar',
      'email': 'owner@thefeed.com',
      'phone': '9876543210',
      'password': 'owner123',
      'address': 'Main Road, Guntur',
      'restaurant': 'Spice Garden',
    });
    await d.insert('users', {
      'role': 'customer',
      'name': 'Demo User',
      'email': 'user@thefeed.com',
      'phone': '9123456780',
      'password': 'user123',
      'address': 'Hostel Block B',
      'restaurant': '',
    });

    // name, price, category, diet, stock, special, emoji, rating, discount%
    const seed = [
      ['Chicken Dum Biryani', 180.0, 'Biryani', 'Non-Veg', 25, 1, '🍛', 4.6, 0],
      ['Veg Biryani', 140.0, 'Biryani', 'Veg', 20, 0, '🍚', 4.3, 15],
      ['Mutton Biryani', 260.0, 'Biryani', 'Non-Veg', 12, 0, '🍖', 4.5, 0],
      ['Andhra Veg Meals', 110.0, 'Meals', 'Veg', 30, 0, '🍱', 4.4, 0],
      ['Masala Dosa', 60.0, 'Snacks', 'Veg', 40, 0, '🥞', 4.5, 10],
      ['Paneer Tikka', 170.0, 'Starters', 'Veg', 18, 0, '🧀', 4.4, 0],
      ['Chicken 65', 160.0, 'Starters', 'Non-Veg', 20, 0, '🍗', 4.2, 0],
      ['Veg Burger', 90.0, 'Pizza & Burgers', 'Veg', 25, 0, '🍔', 4.1, 0],
      ['Margherita Pizza', 199.0, 'Pizza & Burgers', 'Veg', 15, 0, '🍕', 4.3, 20],
      ['Chicken Burger', 130.0, 'Pizza & Burgers', 'Non-Veg', 20, 0, '🍔', 4.2, 0],
      ['Gulab Jamun', 40.0, 'Desserts', 'Veg', 40, 0, '🍮', 4.6, 20],
      ['Ice Cream Sundae', 80.0, 'Desserts', 'Veg', 30, 0, '🍨', 4.4, 20],
      ['Mango Lassi', 50.0, 'Drinks', 'Veg', 35, 0, '🥭', 4.5, 10],
      ['Filter Coffee', 30.0, 'Drinks', 'Veg', 50, 0, '☕', 4.7, 0],
      // ---- JAIN dishes (no onion, garlic, root vegetables) ----
      ['Jain Veg Thali', 130.0, 'Meals', 'Jain', 20, 1, '🍱', 4.5, 25],
      ['Jain Paneer Tikka', 160.0, 'Starters', 'Jain', 15, 0, '🧀', 4.3, 0],
      ['Jain Pav Bhaji', 100.0, 'Snacks', 'Jain', 25, 0, '🥘', 4.4, 10],
      ['Jain Pizza', 180.0, 'Pizza & Burgers', 'Jain', 12, 0, '🍕', 4.2, 0],
      ['Jain Dal Tadka Rice', 95.0, 'Meals', 'Jain', 25, 0, '🍛', 4.3, 0],
      ['Jain Sandwich', 70.0, 'Snacks', 'Jain', 30, 0, '🥪', 4.1, 0],
    ];
    for (final s in seed) {
      await d.insert('menu', {
        'owner_id': 1,
        'name': s[0],
        'price': s[1],
        'category': s[2],
        'diet': s[3],
        'stock': s[4],
        'is_special': s[5],
        'sold_out': 0,
        'emoji': s[6],
        'image': '',
        'rating': s[7],
        'discount': s[8],
      });
    }
  }

  // ----- USERS / AUTH -----
  /// Returns the new user id, or -1 if the email is already registered.
  static Future<int> signup(Map<String, dynamic> u) async {
    final d = await db;
    final ex = await d.query('users', where: 'email = ?', whereArgs: [u['email']]);
    if (ex.isNotEmpty) return -1;
    return d.insert('users', u);
  }

  static Future<Map<String, dynamic>?> login(String email, String pw) async {
    final r = await (await db).query('users',
        where: 'email = ? AND password = ?',
        whereArgs: [email.toLowerCase(), pw]);
    return r.isEmpty ? null : Map<String, dynamic>.from(r.first);
  }

  static Future<Map<String, dynamic>?> userById(int id) async {
    final r = await (await db).query('users', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Map<String, dynamic>.from(r.first);
  }

  static Future<void> updateUser(int id, Map<String, dynamic> m) async =>
      (await db).update('users', m, where: 'id = ?', whereArgs: [id]);

  static Future<void> setSession(int userId) async {
    final d = await db;
    await d.delete('session');
    await d.insert('session', {'user_id': userId});
  }

  static Future<void> clearSession() async => (await db).delete('session');

  static Future<Map<String, dynamic>?> sessionUser() async {
    final r = await (await db).rawQuery(
        'SELECT u.* FROM session s JOIN users u ON u.id = s.user_id LIMIT 1');
    return r.isEmpty ? null : Map<String, dynamic>.from(r.first);
  }

  // ----- MENU -----
  static const _menuJoin =
      'SELECT m.*, u.restaurant AS restaurant FROM menu m '
      'LEFT JOIN users u ON u.id = m.owner_id ';

  static Future<List<Map<String, dynamic>>> menu() async => (await db)
      .rawQuery('${_menuJoin}ORDER BY m.is_special DESC, m.name');

  static Future<List<Map<String, dynamic>>> menuByOwner(int ownerId) async =>
      (await db).query('menu',
          where: 'owner_id = ?',
          whereArgs: [ownerId],
          orderBy: 'is_special DESC, name');

  static Future<void> insertMenu(Map<String, dynamic> m) async =>
      (await db).insert('menu', m);

  /// Finds a dish of this owner with the same name (ignores case and spaces).
  static Future<Map<String, dynamic>?> findDish(
      int ownerId, String name) async {
    final r = await (await db).query('menu',
        where: 'owner_id = ? AND LOWER(TRIM(name)) = ?',
        whereArgs: [ownerId, name.trim().toLowerCase()]);
    return r.isEmpty ? null : Map<String, dynamic>.from(r.first);
  }

  static Future<void> updateMenu(int id, Map<String, dynamic> m) async =>
      (await db).update('menu', m, where: 'id = ?', whereArgs: [id]);

  static Future<void> deleteMenu(int id) async {
    final d = await db;
    await d.delete('menu', where: 'id = ?', whereArgs: [id]);
    await d.delete('cart', where: 'dish_id = ?', whereArgs: [id]);
  }

  // ----- CART (saved per user) -----
  static Future<List<Map<String, dynamic>>> loadCart(int userId) async =>
      (await db).rawQuery(
          'SELECT c.qty AS cqty, m.*, u.restaurant AS restaurant '
          'FROM cart c JOIN menu m ON m.id = c.dish_id '
          'LEFT JOIN users u ON u.id = m.owner_id WHERE c.user_id = ?',
          [userId]);

  static Future<void> setCart(int userId, int dishId, int qty) async {
    final d = await db;
    if (qty <= 0) {
      await d.delete('cart',
          where: 'user_id = ? AND dish_id = ?', whereArgs: [userId, dishId]);
    } else {
      await d.insert('cart', {'user_id': userId, 'dish_id': dishId, 'qty': qty},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  static Future<void> clearCart(int userId) async =>
      (await db).delete('cart', where: 'user_id = ?', whereArgs: [userId]);

  // ----- ORDERS -----
  static Future<bool> placeOrder(
      Map<String, dynamic> order, int dishId, int qty) async {
    final d = await db;
    final r = await d.query('menu',
        columns: ['stock'], where: 'id = ?', whereArgs: [dishId]);
    if (r.isEmpty || (r.first['stock'] as int) < qty) return false;
    await d.insert('orders', order);
    await d.rawUpdate(
        'UPDATE menu SET stock = stock - ? WHERE id = ?', [qty, dishId]);
    return true;
  }

  static Future<List<Map<String, dynamic>>> ordersByCustomer(int id) async =>
      (await db).query('orders',
          where: 'customer_id = ?', whereArgs: [id], orderBy: 'id DESC');

  static Future<List<Map<String, dynamic>>> ordersByOwner(int id) async =>
      (await db).query('orders',
          where: 'owner_id = ?', whereArgs: [id], orderBy: 'id DESC');

  static Future<void> updateStatus(int id, String status) async =>
      (await db).update('orders', {'status': status},
          where: 'id = ?', whereArgs: [id]);

  static Future<void> deleteOrder(int id) async =>
      (await db).delete('orders', where: 'id = ?', whereArgs: [id]);

  static Future<int> deliveredCount(int customerId) async {
    final r = await (await db).rawQuery(
        'SELECT COUNT(*) AS c FROM orders WHERE customer_id = ? AND status = ?',
        [customerId, 'Delivered']);
    return (r.first['c'] as int?) ?? 0;
  }

  static Future<double> earnings(int ownerId) async {
    final r = await (await db).rawQuery(
        'SELECT SUM(total) AS t FROM orders WHERE owner_id = ? AND status = ?',
        [ownerId, 'Delivered']);
    return ((r.first['t'] as num?) ?? 0).toDouble();
  }
}

// ---------------------------------------------------------------------------
// CART (kept in memory AND saved in the database for the logged-in customer)
// ---------------------------------------------------------------------------
class Cart extends ChangeNotifier {
  int userId = 0;
  final Map<int, Map<String, dynamic>> dishes = {};
  final Map<int, int> qty = {};

  int get count => qty.values.fold(0, (a, b) => a + b);

  double get total => qty.entries
      .fold(0.0, (s, e) => s + eff(dishes[e.key]!) * e.value);

  Future<void> load(int uid) async {
    userId = uid;
    dishes.clear();
    qty.clear();
    final rows = await DB.loadCart(uid);
    for (final r in rows) {
      final m = Map<String, dynamic>.from(r);
      final id = m['id'] as int;
      qty[id] = m['cqty'] as int;
      dishes[id] = m;
    }
    notifyListeners();
  }

  void add(Map<String, dynamic> d) {
    final id = d['id'] as int;
    final cur = qty[id] ?? 0;
    if (cur >= (d['stock'] as int)) return;
    dishes[id] = d;
    qty[id] = cur + 1;
    DB.setCart(userId, id, cur + 1);
    notifyListeners();
  }

  void remove(int id) {
    final cur = qty[id] ?? 0;
    if (cur <= 1) {
      qty.remove(id);
      dishes.remove(id);
      DB.setCart(userId, id, 0);
    } else {
      qty[id] = cur - 1;
      DB.setCart(userId, id, cur - 1);
    }
    notifyListeners();
  }

  Future<void> clear() async {
    qty.clear();
    dishes.clear();
    await DB.clearCart(userId);
    notifyListeners();
  }

  /// Used on logout: forget in-memory items (database copy stays saved).
  void reset() {
    userId = 0;
    qty.clear();
    dishes.clear();
    notifyListeners();
  }
}

final cart = Cart();

// ---------------------------------------------------------------------------
// SMALL REUSABLE WIDGETS
// ---------------------------------------------------------------------------
class FeedLogo extends StatelessWidget {
  final double size;
  const FeedLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [kOrange, kPink],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(size * 0.32),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))
              ],
            ),
            child: Center(
              child: Transform.rotate(
                angle: -0.25,
                child: Icon(Icons.local_pizza_rounded,
                    color: Colors.white, size: size * 0.58),
              ),
            ),
          ),
          Positioned(
            right: -size * 0.08,
            top: -size * 0.08,
            child: Container(
              padding: EdgeInsets.all(size * 0.06),
              decoration: const BoxDecoration(
                  color: Color(0xFFFFD60A), shape: BoxShape.circle),
              child: Icon(Icons.bolt_rounded,
                  size: size * 0.26, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

class FeedWordmark extends StatelessWidget {
  final double size;
  const FeedWordmark({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      const TextSpan(children: [
        TextSpan(text: 'the ', style: TextStyle(fontWeight: FontWeight.w300)),
        TextSpan(
            text: 'feed',
            style: TextStyle(fontWeight: FontWeight.w900, color: kPink)),
      ]),
      style: TextStyle(fontSize: size, letterSpacing: -0.5),
    );
  }
}

/// Shows the owner's photo when there is one, otherwise the chosen icon.
class DishImage extends StatelessWidget {
  final Map<String, dynamic> dish;
  final double size;
  const DishImage({super.key, required this.dish, this.size = 90});

  Widget fallback() {
    final pal = palettes[(dish['id'] as int) % palettes.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: pal,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
      ),
      alignment: Alignment.center,
      child: Text('${dish['emoji'] ?? '🍽️'}',
          style: TextStyle(fontSize: size * 0.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final img = '${dish['image'] ?? ''}';
    Widget child;
    if (img.isEmpty) {
      child = fallback();
    } else if (img.startsWith('http')) {
      child = Image.network(img,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback());
    } else {
      child = Image.file(File(img),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback());
    }
    return ClipRRect(borderRadius: BorderRadius.circular(14), child: child);
  }
}

class DietMark extends StatelessWidget {
  final String diet;
  const DietMark({super.key, required this.diet});

  @override
  Widget build(BuildContext context) {
    final c = diet == 'Non-Veg' ? Colors.red : Colors.green;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        border: Border.all(color: c, width: 1.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(child: Icon(Icons.circle, size: 8, color: c)),
    );
  }
}

class PriceTag extends StatelessWidget {
  final Map<String, dynamic> m;
  final double size;
  final bool badge;
  const PriceTag({super.key, required this.m, this.size = 16, this.badge = true});

  @override
  Widget build(BuildContext context) {
    final off = (m['discount'] as num) > 0;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text(rs(eff(m)),
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: size)),
        if (off)
          Text(rs(m['price']),
              style: TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: Colors.grey,
                  fontSize: size - 3)),
        if (off && badge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
                color: Colors.green, borderRadius: BorderRadius.circular(4)),
            child: Text('${m['discount']}% OFF',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}

class QtyStepper extends StatelessWidget {
  final Map<String, dynamic> dish;
  final int qty;
  const QtyStepper({super.key, required this.dish, required this.qty});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: kOrange),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => cart.remove(dish['id'] as int),
            child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.remove, size: 18, color: kOrange)),
          ),
          Text('$qty',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: kOrange)),
          InkWell(
            onTap: () => cart.add(dish),
            child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.add, size: 18, color: kOrange)),
          ),
        ],
      ),
    );
  }
}

AppBar feedAppBar(String role) => AppBar(
      titleSpacing: 14,
      title: const Row(children: [
        FeedLogo(size: 34),
        SizedBox(width: 12),
        FeedWordmark(size: 24),
      ]),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: Colors.black12, borderRadius: BorderRadius.circular(20)),
          child: Text(role,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ],
    );

Future<bool> confirmDelete(BuildContext context, String what) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirm delete'),
      content: Text('Delete $what?'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete')),
      ],
    ),
  );
  return ok ?? false;
}

/// Opens the right home screen for the account's role.
Future<void> openHome(NavigatorState nav, Map<String, dynamic> user) async {
  me = user;
  if (user['role'] == 'customer') {
    await cart.load(user['id'] as int);
  }
  nav.pushAndRemoveUntil(
    MaterialPageRoute(
        builder: (_) => user['role'] == 'owner'
            ? const OwnerHome()
            : const CustomerHome()),
    (r) => false,
  );
}

// ---------------------------------------------------------------------------
// APP + SPLASH (delivery rider with phone rides across the screen)
// ---------------------------------------------------------------------------
class TheFeedApp extends StatelessWidget {
  const TheFeedApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'The Feed',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: kOrange,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF7F7F9),
        ),
        home: const SplashPage(),
      );
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController ctl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3800));

  @override
  void initState() {
    super.initState();
    ctl.forward().whenComplete(next);
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> next() async {
    final user = await DB.sessionUser();
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (user == null) {
      nav.pushReplacement(MaterialPageRoute(builder: (_) => const AuthPage()));
    } else {
      await openHome(nav, user); // remembered login: go straight in
    }
  }

  Widget rider() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 6)
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.phone_android, color: kPink, size: 18),
                SizedBox(width: 4),
                Text('Order on the way!',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.delivery_dining, size: 96, color: kOrange),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: Colors.white,
      body: AnimatedBuilder(
        animation: ctl,
        builder: (_, __) {
          final t = Curves.easeInOut.transform(ctl.value);
          final x = -170 + (w + 340) * t;
          final bob = math.sin(ctl.value * 60) * 3;
          final fade = (ctl.value * 2).clamp(0.0, 1.0);
          return Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: fade,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FeedLogo(size: 100),
                      SizedBox(height: 22),
                      FeedWordmark(size: 46),
                      SizedBox(height: 8),
                      Text('delivering happiness…',
                          style: TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: h * 0.18,
                child: Container(height: 3, color: Colors.black12),
              ),
              Positioned(
                left: x,
                bottom: h * 0.18 + 2 + bob,
                child: rider(),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AUTH: SIGN UP + LOGIN (customer or restaurant owner)
// ---------------------------------------------------------------------------
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final formKey = GlobalKey<FormState>();
  bool isLogin = true;
  bool hide = true;
  String role = 'customer';
  String error = '';
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();
  final address = TextEditingController();
  final restaurant = TextEditingController();

  @override
  void dispose() {
    for (final c in [name, email, phone, password, address, restaurant]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    final nav = Navigator.of(context);
    setState(() => error = '');
    Map<String, dynamic>? user;
    if (isLogin) {
      user = await DB.login(email.text.trim(), password.text);
      if (user == null) {
        setState(() => error = 'Wrong email or password');
        return;
      }
    } else {
      final id = await DB.signup({
        'role': role,
        'name': name.text.trim(),
        'email': email.text.trim().toLowerCase(),
        'phone': phone.text.trim(),
        'password': password.text,
        'address': address.text.trim(),
        'restaurant': role == 'owner' ? restaurant.text.trim() : '',
      });
      if (id < 0) {
        setState(() => error = 'This email is already registered. Please log in.');
        return;
      }
      user = await DB.userById(id);
    }
    await DB.setSession(user!['id'] as int); // remember login
    await openHome(nav, user);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: formKey,
              child: Column(
                children: [
                  const FeedLogo(size: 70),
                  const SizedBox(height: 14),
                  const FeedWordmark(size: 34),
                  const SizedBox(height: 4),
                  Text(isLogin ? 'Welcome back 👋' : 'Create your account',
                      style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 20),
                  if (!isLogin) ...[
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: 'customer',
                            icon: Icon(Icons.person),
                            label: Text('Customer')),
                        ButtonSegment(
                            value: 'owner',
                            icon: Icon(Icons.storefront),
                            label: Text('Restaurant')),
                      ],
                      selected: {role},
                      onSelectionChanged: (s) => setState(() => role = s.first),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: name,
                      decoration: deco('Full name', Icons.person),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter your name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    if (role == 'owner') ...[
                      TextFormField(
                        controller: restaurant,
                        decoration:
                            deco('Restaurant name', Icons.restaurant),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter restaurant name'
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: deco('Phone (10 digits)', Icons.phone),
                      validator: (v) => RegExp(r'^\d{10}$').hasMatch(v ?? '')
                          ? null
                          : 'Enter a valid 10-digit phone number',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: address,
                      decoration: deco(
                          role == 'owner'
                              ? 'Restaurant address'
                              : 'Delivery address',
                          Icons.location_on),
                      validator: (v) => (v == null || v.trim().length < 5)
                          ? 'Enter an address'
                          : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: deco('Email', Icons.email),
                    validator: (v) =>
                        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '')
                            ? null
                            : 'Enter a valid email',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: password,
                    obscureText: hide,
                    decoration: InputDecoration(
                      labelText: 'Password (min 6 characters)',
                      prefixIcon: const Icon(Icons.lock),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                            hide ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => hide = !hide),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 6)
                        ? 'Password must be at least 6 characters'
                        : null,
                  ),
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(error,
                          style: const TextStyle(color: Colors.red)),
                    ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: kOrange,
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: submit,
                      child: Text(isLogin ? 'Log in' : 'Sign up'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      isLogin = !isLogin;
                      error = '';
                    }),
                    child: Text(isLogin
                        ? 'New here? Create an account'
                        : 'Already have an account? Log in'),
                  ),
                  if (isLogin)
                    const Text(
                      'Demo  •  Customer: user@thefeed.com / user123\n'
                      'Owner: owner@thefeed.com / owner123',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PROFILE (shared by customer and owner): view + update details, log out
// ---------------------------------------------------------------------------
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name =
      TextEditingController(text: '${me['name']}');
  late final TextEditingController phone =
      TextEditingController(text: '${me['phone']}');
  late final TextEditingController address =
      TextEditingController(text: '${me['address']}');
  late final TextEditingController restaurant =
      TextEditingController(text: '${me['restaurant']}');
  bool get isOwner => me['role'] == 'owner';

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    address.dispose();
    restaurant.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    final data = {
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      'address': address.text.trim(),
      'restaurant': isOwner ? restaurant.text.trim() : '',
    };
    await DB.updateUser(me['id'] as int, data);
    me = {...me, ...data};
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Profile updated ✅')));
  }

  Future<void> logout() async {
    final nav = Navigator.of(context);
    await DB.clearSession();
    cart.reset();
    me = {};
    nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthPage()), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final initial = '${me['name']}'.isEmpty ? '?' : '${me['name']}'[0].toUpperCase();
    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 42,
              backgroundColor: kOrange,
              child: Text(initial,
                  style: const TextStyle(
                      fontSize: 38,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text('${me['name']}',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          Center(
            child: Text(isOwner ? 'Restaurant owner' : 'Customer',
                style: const TextStyle(color: Colors.black54)),
          ),
          const SizedBox(height: 18),
          TextFormField(
            initialValue: '${me['email']}',
            enabled: false,
            decoration: deco('Email (cannot be changed)', Icons.email),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: name,
            decoration: deco('Full name', Icons.person),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
          ),
          const SizedBox(height: 12),
          if (isOwner) ...[
            TextFormField(
              controller: restaurant,
              decoration: deco('Restaurant name', Icons.restaurant),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Enter restaurant name'
                  : null,
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: deco('Phone', Icons.phone),
            validator: (v) => RegExp(r'^\d{10}$').hasMatch(v ?? '')
                ? null
                : 'Enter a valid 10-digit phone number',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: address,
            maxLines: 2,
            decoration: deco(isOwner ? 'Restaurant address' : 'Delivery address',
                Icons.location_on),
            validator: (v) => (v == null || v.trim().length < 5)
                ? 'Enter an address'
                : null,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: kOrange,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: save,
            icon: const Icon(Icons.save),
            label: const Text('Save changes'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: logout,
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
//                              CUSTOMER SIDE
// ===========================================================================
class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});
  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(onSeeMenu: () => setState(() => tab = 1)),
      const MenuPage(),
      CartTab(onOrdered: () => setState(() => tab = 3)),
      const MyOrdersPage(),
      const ProfilePage(),
    ];
    return Scaffold(
      appBar: feedAppBar('Customer'),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          const NavigationDestination(
              icon: Icon(Icons.restaurant_menu), label: 'Menu'),
          NavigationDestination(
            icon: ListenableBuilder(
              listenable: cart,
              builder: (_, __) => Badge(
                label: Text('${cart.count}'),
                isLabelVisible: cart.count > 0,
                child: const Icon(Icons.shopping_cart),
              ),
            ),
            label: 'Cart',
          ),
          const NavigationDestination(
              icon: Icon(Icons.receipt_long), label: 'Orders'),
          const NavigationDestination(
              icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

// ---------------- HOME: offers slider + specials + deals ----------------
class Offer {
  final String tag, title, sub, emoji;
  final List<Color> colors;
  const Offer(this.tag, this.title, this.sub, this.emoji, this.colors);
}

const offers = [
  Offer('FESTIVE OFFER', 'Diwali Dhamaka', 'Flat 20% off on sweets & desserts',
      '🪔', [Color(0xFFFF8008), Color(0xFFFFC837)]),
  Offer("TODAY'S SPECIAL", 'Dum Biryani Fest', 'Hot, fresh & made in small batches',
      '🍛', [kOrange, kPink]),
  Offer('JAIN CORNER', 'Jain Thali at ₹98', 'No onion, no garlic, pure taste',
      '🍱', [Color(0xFF11998E), Color(0xFF38EF7D)]),
  Offer('ZERO FEES', 'Free delivery all week', 'No platform fee. No hidden charges.',
      '🛵', [Color(0xFF396AFF), Color(0xFF2BC0E4)]),
  Offer('SWEET DEAL', 'Dessert Delight', 'Gulab jamun & sundaes from ₹32',
      '🍨', [Color(0xFFDA22FF), Color(0xFF9733EE)]),
];

class OfferCarousel extends StatefulWidget {
  final VoidCallback onTap;
  const OfferCarousel({super.key, required this.onTap});
  @override
  State<OfferCarousel> createState() => _OfferCarouselState();
}

class _OfferCarouselState extends State<OfferCarousel> {
  final pc = PageController(viewportFraction: 0.92);
  int page = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!pc.hasClients) return;
      pc.animateToPage((page + 1) % offers.length,
          duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 160,
          child: PageView.builder(
            controller: pc,
            itemCount: offers.length,
            onPageChanged: (i) => setState(() => page = i),
            itemBuilder: (_, i) {
              final o = offers[i];
              return GestureDetector(
                onTap: widget.onTap,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: o.colors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text(o.tag,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(height: 8),
                            Text(o.title,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            Text(o.sub,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      ),
                      Text(o.emoji, style: const TextStyle(fontSize: 62)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            offers.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == page ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == page ? kOrange : Colors.black26,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MiniDish extends StatelessWidget {
  final Map<String, dynamic> m;
  const MiniDish({super.key, required this.m});

  @override
  Widget build(BuildContext context) {
    final out = m['sold_out'] == 1 || m['stock'] <= 0;
    return Container(
      width: 148,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              DishImage(dish: m, size: 130),
              if ((m['discount'] as num) > 0)
                Positioned(
                  left: 0,
                  top: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: const BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomRight: Radius.circular(8))),
                    child: Text('${m['discount']}% OFF',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text('${m['name']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('${m['restaurant'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 4),
          PriceTag(m: m, size: 14, badge: false),
          const Spacer(),
          ListenableBuilder(
            listenable: cart,
            builder: (_, __) {
              final q = cart.qty[m['id']] ?? 0;
              if (out) {
                return const Text('Sold out',
                    style: TextStyle(color: Colors.red, fontSize: 12));
              }
              if (q == 0) {
                return SizedBox(
                  width: double.infinity,
                  height: 30,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: kOrange,
                        side: const BorderSide(color: kOrange),
                        padding: EdgeInsets.zero),
                    onPressed: () => cart.add(m),
                    child: const Text('ADD',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                );
              }
              return Center(child: QtyStepper(dish: m, qty: q));
            },
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final VoidCallback onSeeMenu;
  const HomePage({super.key, required this.onSeeMenu});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await DB.menu();
    if (mounted) setState(() => items = r);
  }

  Widget section(String title, List<Map<String, dynamic>> list) {
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              TextButton(
                  onPressed: widget.onSeeMenu, child: const Text('See all')),
            ],
          ),
        ),
        SizedBox(
          height: 275,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 16),
            itemCount: list.length,
            itemBuilder: (_, i) => MiniDish(m: list[i]),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = '${me['name']}'.split(' ').first;
    final specials = items.where((e) => e['is_special'] == 1).toList();
    final deals = items.where((e) => (e['discount'] as num) > 0).toList();
    final jain = items.where((e) => e['diet'] == 'Jain').toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hi $first 👋',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900)),
              const Text('What are you craving today?',
                  style: TextStyle(color: Colors.black54)),
            ],
          ),
        ),
        OfferCarousel(onTap: widget.onSeeMenu),
        section("🔥 Today's specials", specials),
        section('💸 Deals & discounts', deals),
        section('🌿 Jain corner', jain),
      ],
    );
  }
}

// ---------------- MENU (READ with search / filters / sort) ----------------
class MenuPage extends StatefulWidget {
  const MenuPage({super.key});
  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  List<Map<String, dynamic>> items = [];
  String diet = 'All';
  String cat = 'All';
  String query = '';
  String sort = 'Recommended';
  static const sorts = [
    'Recommended',
    'Price: low to high',
    'Price: high to low',
    'Rating',
  ];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await DB.menu();
    if (mounted) setState(() => items = r);
  }

  List<Map<String, dynamic>> get shown {
    final r = items.where((e) {
      if (diet != 'All' && e['diet'] != diet) return false;
      if (cat != 'All' && e['category'] != cat) return false;
      if (query.isNotEmpty &&
          !('${e['name']}'.toLowerCase().contains(query.toLowerCase()))) {
        return false;
      }
      return true;
    }).toList();
    if (sort == 'Price: low to high') {
      r.sort((a, b) => eff(a).compareTo(eff(b)));
    } else if (sort == 'Price: high to low') {
      r.sort((a, b) => eff(b).compareTo(eff(a)));
    } else if (sort == 'Rating') {
      r.sort((a, b) => (b['rating'] as num).compareTo(a['rating'] as num));
    }
    return r;
  }

  Widget categoryItem(String label, String emoji) {
    final selected = cat == label;
    return GestureDetector(
      onTap: () => setState(() => cat = label),
      child: Container(
        width: 74,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: selected ? kOrange : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                    color: selected ? kPink : Colors.black12, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 24)),
            ),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  Widget dishCard(Map<String, dynamic> m) {
    final out = m['sold_out'] == 1 || m['stock'] <= 0;
    final inCart = cart.qty[m['id']] ?? 0;
    final rating = (m['rating'] as num).toDouble();
    final mins = 20 + (m['id'] as int) % 4 * 5;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                DishImage(dish: m, size: 96),
                if (out)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        color: Colors.black54,
                        alignment: Alignment.center,
                        child: const Text('SOLD OUT',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      DietMark(diet: '${m['diet']}'),
                      const SizedBox(width: 6),
                      if (m['diet'] == 'Jain')
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                              color: const Color(0xFFFFE082),
                              borderRadius: BorderRadius.circular(4)),
                          child: const Text('JAIN',
                              style: TextStyle(
                                  fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      Expanded(
                        child: Text('${m['name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                    ],
                  ),
                  Text('${m['restaurant'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.black54)),
                  if (m['is_special'] == 1)
                    const Text("🔥 Today's special",
                        style: TextStyle(
                            color: kPink,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 15, color: Colors.green),
                      Text(' ${rating.toStringAsFixed(1)}  •  $mins min  •  ${m['category']}',
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  PriceTag(m: m),
                  if (!out && m['stock'] <= 10)
                    Text('Only ${m['stock']} left!',
                        style: const TextStyle(
                            color: Colors.red,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (out)
              const SizedBox.shrink()
            else if (inCart == 0)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: kOrange,
                    side: const BorderSide(color: kOrange),
                    padding: const EdgeInsets.symmetric(horizontal: 14)),
                onPressed: () => cart.add(m),
                child: const Text('ADD',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              )
            else
              QtyStepper(dish: m, qty: inCart),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: TextField(
            onChanged: (v) => setState(() => query = v.trim()),
            decoration: InputDecoration(
              hintText: 'Search biryani, dosa, pizza...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        SizedBox(
          height: 84,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            children: [
              categoryItem('All', '🍽️'),
              ...categories.map((c) => categoryItem(c, categoryEmoji[c]!)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All', ...diets]
                        .map((d) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(d),
                                selected: diet == d,
                                onSelected: (_) => setState(() => diet = d),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
              DropdownButton<String>(
                value: sort,
                underline: const SizedBox.shrink(),
                icon: const Icon(Icons.sort),
                items: sorts
                    .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s, style: const TextStyle(fontSize: 12))))
                    .toList(),
                onChanged: (v) => setState(() => sort = v!),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: cart,
            builder: (_, __) {
              final list = shown;
              if (list.isEmpty) {
                return const Center(child: Text('No dishes found 🍽️'));
              }
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => dishCard(list[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------- CART TAB (saved in DB) + CHECKOUT ----------------
class CartTab extends StatefulWidget {
  final VoidCallback onOrdered;
  const CartTab({super.key, required this.onOrdered});
  @override
  State<CartTab> createState() => _CartTabState();
}

class _CartTabState extends State<CartTab> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name =
      TextEditingController(text: '${me['name']}');
  late final TextEditingController phone =
      TextEditingController(text: '${me['phone']}');
  late final TextEditingController address =
      TextEditingController(text: '${me['address']}');
  String slot = slots.first;

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    address.dispose();
    super.dispose();
  }

  Future<void> placeOrder() async {
    if (cart.count == 0) return;
    if (!formKey.currentState!.validate()) return;
    final failed = <String>[];
    for (final e in cart.qty.entries.toList()) {
      final d = cart.dishes[e.key]!;
      final ok = await DB.placeOrder({
        'customer_id': me['id'],
        'owner_id': d['owner_id'],
        'restaurant': d['restaurant'] ?? '',
        'customer': name.text.trim(),
        'phone': phone.text.trim(),
        'address': address.text.trim(),
        'item': d['name'],
        'qty': e.value,
        'total': eff(d) * e.value,
        'slot': slot,
        'status': 'Pending',
      }, e.key, e.value);
      if (!ok) failed.add('${d['name']}');
    }
    await cart.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failed.isEmpty
            ? 'Order placed! 🎉'
            : 'Placed, but out of stock: ${failed.join(', ')}')));
    widget.onOrdered();
  }

  Widget billRow(String l, String r, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
            Text(r,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cart,
      builder: (_, __) {
        if (cart.count == 0) {
          return const Center(
              child: Text('Your cart is empty 🛒\nAdd some tasty dishes!',
                  textAlign: TextAlign.center));
        }
        return Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              const Text('Your saved cart',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              for (final e in cart.qty.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: DishImage(dish: cart.dishes[e.key]!, size: 52),
                  title: Text('${cart.dishes[e.key]!['name']}'),
                  subtitle: Text(
                      '${cart.dishes[e.key]!['restaurant'] ?? ''} • ${rs(eff(cart.dishes[e.key]!))}'),
                  trailing: QtyStepper(dish: cart.dishes[e.key]!, qty: e.value),
                ),
              const Divider(),
              const SizedBox(height: 8),
              TextFormField(
                controller: name,
                decoration: deco('Your name', Icons.person),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: deco('Phone (10 digits)', Icons.phone),
                validator: (v) => RegExp(r'^\d{10}$').hasMatch(v ?? '')
                    ? null
                    : 'Enter a valid 10-digit phone number',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: address,
                maxLines: 2,
                decoration: deco('Delivery address', Icons.location_on),
                validator: (v) => (v == null || v.trim().length < 5)
                    ? 'Enter your delivery address'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: slot,
                decoration: deco('Delivery time (schedule)', Icons.schedule),
                items: slots
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => slot = v!),
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      billRow('Item total', rs(cart.total)),
                      billRow('Delivery fee', '₹0'),
                      billRow('Platform fee (0% commission)', '₹0'),
                      const Divider(),
                      billRow('To pay', rs(cart.total), bold: true),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: kOrange),
                onPressed: placeOrder,
                icon: const Icon(Icons.check_circle),
                label: Text('Place order • ${rs(cart.total)}'),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------- CUSTOMER ORDERS (read only) ----------------
class MyOrdersPage extends StatefulWidget {
  const MyOrdersPage({super.key});
  @override
  State<MyOrdersPage> createState() => _MyOrdersPageState();
}

class _MyOrdersPageState extends State<MyOrdersPage> {
  List<Map<String, dynamic>> orders = [];
  int delivered = 0;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await DB.ordersByCustomer(me['id'] as int);
    final c = await DB.deliveredCount(me['id'] as int);
    if (!mounted) return;
    setState(() {
      orders = r;
      delivered = c;
      loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final stamps = delivered % 5;
    return Column(
      children: [
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Text('Loyalty stamps  '),
                ...List.generate(
                  5,
                  (i) => Icon(
                      i < stamps
                          ? Icons.local_pizza
                          : Icons.local_pizza_outlined,
                      color: kOrange),
                ),
                const Spacer(),
                Text(
                    delivered > 0 && stamps == 0
                        ? '🎉 Free item!'
                        : '${5 - stamps} to free',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        Expanded(
          child: orders.isEmpty
              ? const Center(child: Text('No orders yet'))
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView.builder(
                    itemCount: orders.length,
                    itemBuilder: (_, i) {
                      final o = orders[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: ListTile(
                          title: Text('${o['item']} × ${o['qty']}'),
                          subtitle: Text(
                              '${o['restaurant']} • ${rs(o['total'])}\n${o['slot']} • ${o['address']}'),
                          isThreeLine: true,
                          trailing: Chip(
                            label: Text('${o['status']}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 11)),
                            backgroundColor: statusColor('${o['status']}'),
                            side: BorderSide.none,
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

// ===========================================================================
//                            RESTAURANT OWNER SIDE
// ===========================================================================
class OwnerHome extends StatefulWidget {
  const OwnerHome({super.key});
  @override
  State<OwnerHome> createState() => _OwnerHomeState();
}

class _OwnerHomeState extends State<OwnerHome> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const OwnerDishesPage(),
      const OwnerOrdersPage(),
      const ProfilePage(),
    ];
    return Scaffold(
      appBar: feedAppBar('Owner • ${me['restaurant']}'),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.fastfood), label: 'Dishes'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long), label: 'Orders'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

// ---------------- OWNER: DISHES (CRUD) ----------------
class OwnerDishesPage extends StatefulWidget {
  const OwnerDishesPage({super.key});
  @override
  State<OwnerDishesPage> createState() => _OwnerDishesPageState();
}

class _OwnerDishesPageState extends State<OwnerDishesPage> {
  List<Map<String, dynamic>> items = [];
  double earned = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await DB.menuByOwner(me['id'] as int);
    final e = await DB.earnings(me['id'] as int);
    if (mounted) {
      setState(() {
        items = r;
        earned = e;
      });
    }
  }

  Future<void> openForm([Map<String, dynamic>? item]) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => ItemFormPage(item: item)));
    load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kOrange,
        foregroundColor: Colors.white,
        onPressed: () => openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add dish'),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kOrange, kPink]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet,
                    color: Colors.white, size: 34),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Earnings: ${rs(earned)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                      const Text('Commission paid: ₹0  (others charge 20–30%)',
                          style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text('No dishes yet.\nTap "Add dish" to start.',
                        textAlign: TextAlign.center))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final m = items[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        child: ListTile(
                          leading: DishImage(dish: m, size: 52),
                          title: Row(
                            children: [
                              DietMark(diet: '${m['diet']}'),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text('${m['name']}',
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                          subtitle: Text(
                              '${rs(m['price'])}'
                              '${(m['discount'] as num) > 0 ? ' (${m['discount']}% off → ${rs(eff(m))})' : ''}'
                              ' • ${m['category']}\n'
                              'Stock ${m['stock']}'
                              '${m['is_special'] == 1 ? ' • Special' : ''}'
                              '${m['sold_out'] == 1 ? ' • SOLD OUT' : ''}'),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => openForm(m),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Colors.red),
                                onPressed: () async {
                                  if (await confirmDelete(
                                      context, '${m['name']}')) {
                                    await DB.deleteMenu(m['id']);
                                    load();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------- OWNER: ADD / EDIT DISH (photo from gallery or icon) ----------------
class ItemFormPage extends StatefulWidget {
  final Map<String, dynamic>? item;
  const ItemFormPage({super.key, this.item});
  @override
  State<ItemFormPage> createState() => _ItemFormPageState();
}

class _ItemFormPageState extends State<ItemFormPage> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController price;
  late final TextEditingController stock;
  late final TextEditingController discount;
  late String category;
  late String diet;
  late String emoji;
  late String imagePath;
  late bool special;
  late bool soldOut;

  @override
  void initState() {
    super.initState();
    final m = widget.item;
    name = TextEditingController(text: m == null ? '' : '${m['name']}');
    price = TextEditingController(
        text: m == null ? '' : (m['price'] as num).toStringAsFixed(0));
    stock = TextEditingController(text: m == null ? '' : '${m['stock']}');
    discount = TextEditingController(text: m == null ? '0' : '${m['discount']}');
    category = m == null ? categories.first : '${m['category']}';
    diet = m == null ? diets.first : '${m['diet']}';
    emoji = m == null ? emojis.first : '${m['emoji']}';
    if (!emojis.contains(emoji)) emoji = emojis.first;
    imagePath = m == null ? '' : '${m['image'] ?? ''}';
    special = m != null && m['is_special'] == 1;
    soldOut = m != null && m['sold_out'] == 1;
  }

  @override
  void dispose() {
    name.dispose();
    price.dispose();
    stock.dispose();
    discount.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 900, imageQuality: 80);
    if (x == null) return;
    // copy into app storage so the photo is kept
    final dir = await getDatabasesPath();
    final saved = await File(x.path).copy(
        p.join(dir, 'dish_${DateTime.now().millisecondsSinceEpoch}.jpg'));
    if (mounted) setState(() => imagePath = saved.path);
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    final data = <String, dynamic>{
      'name': name.text.trim(),
      'price': double.parse(price.text),
      'category': category,
      'diet': diet,
      'stock': int.parse(stock.text),
      'is_special': special ? 1 : 0,
      'sold_out': soldOut ? 1 : 0,
      'emoji': emoji,
      'image': imagePath,
      'discount': int.parse(discount.text),
    };
    final existing = await DB.findDish(me['id'] as int, name.text);
    String message = '';
    if (widget.item == null) {
      if (existing != null) {
        // Dish already exists: update it instead of adding a duplicate.
        if (imagePath.isEmpty) data['image'] = existing['image'] ?? '';
        await DB.updateMenu(existing['id'] as int, data);
        message = '"${existing['name']}" already existed, so it was updated.';
      } else {
        data['owner_id'] = me['id'];
        data['rating'] = 4.0;
        await DB.insertMenu(data);
        message = 'Dish added.';
      }
    } else {
      if (existing != null && existing['id'] != widget.item!['id']) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Another dish with this name already exists.')));
        return;
      }
      await DB.updateMenu(widget.item!['id'] as int, data);
      message = 'Dish updated.';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: Text(widget.item == null ? 'Add dish' : 'Edit dish')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: ListView(
            children: [
              Center(
                child: DishImage(
                    dish: {'id': 1, 'emoji': emoji, 'image': imagePath},
                    size: 130),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: pickImage,
                    icon: const Icon(Icons.photo_library),
                    label: Text(imagePath.isEmpty ? 'Add photo' : 'Change photo'),
                  ),
                  if (imagePath.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => setState(() => imagePath = ''),
                      child: const Text('Use icon'),
                    ),
                  ],
                ],
              ),
              const Center(
                child: Text('No photo? The selected icon is shown instead.',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: name,
                decoration: deco('Dish name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter dish name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: deco('Price (₹)'),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  return (n == null || n <= 0) ? 'Enter a valid price' : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: discount,
                keyboardType: TextInputType.number,
                decoration: deco('Discount % (0 for none)'),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  return (n == null || n < 0 || n > 90)
                      ? 'Enter 0 to 90'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: category,
                decoration: deco('Category'),
                items: categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => category = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: diet,
                decoration: deco('Diet type (Veg / Non-Veg / Jain)'),
                items: diets
                    .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                    .toList(),
                onChanged: (v) => setState(() => diet = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: stock,
                keyboardType: TextInputType.number,
                decoration: deco('Stock (plates available)'),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  return (n == null || n < 0) ? 'Enter a valid stock' : null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: emoji,
                decoration: deco('Dish icon (used when there is no photo)'),
                items: emojis
                    .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e, style: const TextStyle(fontSize: 24))))
                    .toList(),
                onChanged: (v) => setState(() => emoji = v!),
              ),
              SwitchListTile(
                title: const Text("Today's special"),
                value: special,
                onChanged: (v) => setState(() => special = v),
              ),
              SwitchListTile(
                title: const Text('Mark as sold out'),
                value: soldOut,
                onChanged: (v) => setState(() => soldOut = v),
              ),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: kOrange,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: save,
                child: Text(widget.item == null ? 'Save dish' : 'Update dish'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- OWNER: ORDERS (READ + UPDATE status + DELETE) ----------------
class OwnerOrdersPage extends StatefulWidget {
  const OwnerOrdersPage({super.key});
  @override
  State<OwnerOrdersPage> createState() => _OwnerOrdersPageState();
}

class _OwnerOrdersPageState extends State<OwnerOrdersPage> {
  List<Map<String, dynamic>> orders = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await DB.ordersByOwner(me['id'] as int);
    if (mounted) setState(() => orders = r);
  }

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const Center(child: Text('No orders yet'));
    }
    return RefreshIndicator(
      onRefresh: load,
      child: ListView.builder(
        itemCount: orders.length,
        itemBuilder: (_, i) {
          final o = orders[i];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '#${o['id']}  ${o['item']} × ${o['qty']}  •  ${rs(o['total'])}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  Text('${o['customer']} (${o['phone']})'),
                  Text('📍 ${o['address']}'),
                  Text('🕒 ${o['slot']}'),
                  Row(
                    children: [
                      const Text('Status: '),
                      DropdownButton<String>(
                        value: '${o['status']}',
                        items: statuses
                            .map((s) =>
                                DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (v) async {
                          await DB.updateStatus(o['id'], v!);
                          load();
                        },
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          if (await confirmDelete(
                              context, 'order #${o['id']}')) {
                            await DB.deleteOrder(o['id']);
                            load();
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}