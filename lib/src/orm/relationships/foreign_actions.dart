enum ForeignKeyAction {
  cascade('CASCADE'),
  restrict('RESTRICT'),
  setNull('SET NULL'),
  noAction('');

  const ForeignKeyAction(this.sql);

  final String sql;
}
