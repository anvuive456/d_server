import 'package:d_server/d_server.dart';

class CreateTask extends Migration {
  @override
  String get version => '20251026162521';

  @override
  Future<void> up() async {
    await createTable('tasks', (table) {
      table.serial('id').primaryKey().finalize();
      table.string('name').notNull().finalize();
      table.boolean('completed').defaultValue('false').notNull().finalize();
      table
          .integer('todo_id')
          .notNull()
          .finalize(); // Foreign key to todos table
      table.timestamps();
    });

    await addForeignKey(
      'tasks',
      'todo_id',
      'todos',
      referencedColumn: 'id',
      onDelete: ForeignKeyAction.cascade,
      onUpdate: ForeignKeyAction.cascade,
    );
  }

  @override
  Future<void> down() async {
    await dropForeignKey('tasks', 'todo_id');
    await dropTable('tasks');
  }
}
