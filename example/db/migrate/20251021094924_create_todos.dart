import 'package:d_server/d_server.dart';

class CreateTodos extends Migration {
  @override
  String get version => '20251021094924';

  @override
  Future<void> up() async {
    await createTable('todos', (table) {
      table.serial('id').primaryKey().finalize();
      table.string('title').notNull().finalize();
      table.boolean('completed').defaultValue('false').notNull().finalize();
      table.timestamps();
    });
  }

  @override
  Future<void> down() async {
    await dropTable('todos');
  }
}
