require 'active_support/all'
require 'securerandom'

require 'automodel/automodel'
require 'automodel/errors'

module Automodel
  ## A utility object that issues the actual database inspection commands and returns the table,
  ## column, primary-key, and foreign-key data.
  ##
  class SchemaInspector
    ## rubocop:disable all

    ## Class-Instance variable: `known_adapters` is a Hash of adapters registered via
    ## {Automodel::SchemaInspector.register_adapter}.
    ##
    @known_adapters = {}
    def self.known_adapters; @known_adapters; end
    def known_adapters; self.class.known_adapters; end
    ## rubocop:enable all

    ## "Registers" an adapter with the Automodel::SchemaInspector. This allows for alternate
    ## mechanisms of procuring lists of tables, columns, primary keys, and/or foreign keys from an
    ## adapter that may not itself support `#tables`/`#columns`/`#primary_key`/`#foreign_keys`.
    ##
    ##
    ## @param adapter [String, Symbol]
    ##   The "adapter" value used to match that given in the connection spec. It is with this value
    ##   that the adapter being registered is matched to an existing database pool/connection.
    ##
    ## @param tables [Proc]
    ##   The Proc to `#call` to request a list of table names. The Proc will be called with one
    ##   parameter: a database connection.
    ##
    ## @param columns [Proc]
    ##   The Proc to `#call` to request a list of columns for a specific table. The Proc will be
    ##   called with two parameters: a database connection and a table name.
    ##
    ## @param primary_key [Proc]
    ##   The Proc to `#call` to request the primary key for a specific table. The Proc will be
    ##   called with two parameters: a database connection and a table name.
    ##
    ## @param foreign_keys [Proc]
    ##   The Proc to `#call` to request a list of foreign keys for a specific table. The Proc will
    ##   be called with two parameters: a database connection and a table name.
    ##
    ##
    ## @raise [Automodel::AdapterAlreadyRegisteredError]
    ##
    def self.register_adapter(adapter:, tables:, columns:, primary_key:, foreign_keys: nil)
      adapter = adapter.to_sym.downcase
      raise Automodel::AdapterAlreadyRegisteredError, adapter if known_adapters.key? adapter

      known_adapters[adapter] = { tables: tables,
                                  columns: columns,
                                  primary_key: primary_key,
                                  foreign_keys: foreign_keys }
    end

    ## @param connection_handler [ActiveRecord::ConnectionHandling]
    ##   The connection pool/handler (an object that implements ActiveRecord::ConnectionHandling) to
    ##   inspect and map out.
    ##
    def initialize(connection_handler)
      @connection = connection_handler.connection
      adapter = connection_handler.connection_pool.spec.config[:adapter]

      @registration = known_adapters[adapter.to_sym] || {}
    end

    ## Returns a list of table names in the target database.
    ##
    ## If a matching Automodel::SchemaInspector registration is found for the connection's adapter,
    ## and that registration specified a `:tables` Proc, the Proc is called. Otherwise, the standard
    ## connection `#tables` is returned.
    ##
    ##
    ## @return [Array<String>]
    ##
    def tables
      @tables ||= if @registration[:tables].present?
                    @registration[:tables].call(@connection)
                  else
                    @connection.tables
                  end
    end

    ## Returns a list of columns for the given table.
    ##
    ## If a matching Automodel::SchemaInspector registration is found for the connection's adapter,
    ## and that registration specified a `:columns` Proc, the Proc is called. Otherwise, the
    ## standard connection `#columns` is returned.
    ##
    ##
    ## @param table_name [String]
    ##   The table whose columns should be fetched.
    ##
    ##
    ## @return [Array<ActiveRecord::ConnectionAdapters::Column>]
    ##
    def columns(table_name)
      table_name = table_name.to_s

      @columns ||= {}
      @columns[table_name] ||= if @registration[:columns].present?
                                 @registration[:columns].call(@connection, table_name)
                               else
                                 @connection.columns(table_name)
                               end
    end

    ## Returns the primary key for the given table.
    ##
    ## If a matching Automodel::SchemaInspector registration is found for the connection's adapter,
    ## and that registration specified a `:primary_key` Proc, the Proc is called. Otherwise, the
    ## standard connection `#primary_key` is returned.
    ##
    ##
    ## @param table_name [String]
    ##   The table whose primary key should be fetched.
    ##
    ##
    ## @return [String, Array<String>]
    ##
    def primary_key(table_name)
      table_name = table_name.to_s

      @primary_keys ||= {}
      @primary_keys[table_name] ||= if @registration[:primary_key].present?
                                      @registration[:primary_key].call(@connection, table_name)
                                    else
                                      @connection.primary_key(table_name)
                                    end
    end

    ## Returns a list of foreign keys for the given table.
    ##
    ## If a matching Automodel::SchemaInspector registration is found for the connection's adapter,
    ## and that registration specified a `:foreign_keys` Proc, the Proc is called. Otherwise, the
    ## standard connection `#foreign_keys` is attempted. If that call to ``#foreign_keys` raises a
    ## ::NoMethodError or ::NotImplementedError, a best-effort attempt is made to build a list of
    ## foreign keys based on table and column names.
    ##
    ##
    ## @param table_name [String]
    ##   The table whose foreign keys should be fetched.
    ##
    ##
    ## @return [Array<ActiveRecord::ConnectionAdapters::ForeignKeyDefinition>]
    ##
    def foreign_keys(table_name)
      table_name = table_name.to_s

      @foreign_keys ||= {}
      @foreign_keys[table_name] ||= begin
        if @registration[:foreign_keys].present?
          @registration[:foreign_keys].call(@connection, table_name)
        else
          begin
            @connection.foreign_keys(table_name)
          rescue ::NoMethodError, ::NotImplementedError
            ## Not all ActiveRecord adapters support `#foreign_keys`. When this happens, we'll make
            ## a best-effort attempt to intuit relationships from the table and column names.
            ##
            columns(table_name).map do |column|
              id_pattern = %r{(?:_id|Id)$}
              next unless column.name =~ id_pattern

              target_table = column.name.sub(id_pattern, '')
              next unless target_table.in? tables

              target_column = primary_key(qualified_name(target_table, context: table_name))
              next unless target_column.in? ['id', 'Id', 'ID', column.name]

              ActiveRecord::ConnectionAdapters::ForeignKeyDefinition.new(
                table_name.split('.').last,
                target_table,
                name: "FK_#{SecureRandom.uuid.delete('-')}",
                column:  column.name,
                primary_key: target_column,
                on_update: nil,
                on_delete: nil
              )
            end.compact
          end
        end
      end
    end

    private

    ## Returns a qualified table name.
    ##
    ##
    ## @param table_name [String]
    ##   The name to qualify.
    ##
    ## @param context [String]
    ##   The name of an existing table from whose namespace we want to be able to reach the first
    ##   table.
    ##
    ##
    ## @return [String]
    ##
    def qualified(table_name, context:)
      return table_name if table_name['.'].present?
      return table_name if context['.'].blank?

      "#{context.sub(%r{[^.]*$}, '')}#{table_name}"
    end

    ## Returns an unqualified table name.
    ##
    def unqualified(table_name)
      table_name.split('.').last
    end
  end
end
