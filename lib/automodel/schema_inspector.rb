require 'active_support/all'
require 'securerandom'

require 'automodel/automodel'
require 'automodel/errors'

module Automodel
  class SchemaInspector
    ## rubocop:disable all

    ## Class-Instance variable ...
    ##
    @known_adapters = {}
    def self.known_adapters; @known_adapters; end
    def known_adapters; self.class.known_adapters; end
    ## rubocop:enable all

    def self.register_adapter(adapter:, tables:, columns:, primary_key:, foreign_keys: nil)
      adapter = adapter.to_sym.downcase
      raise Automodel::AdapterAlreadyRegistered, adapter if known_adapters.key? adapter

      known_adapters[adapter] = { tables: tables,
                                  columns: columns,
                                  primary_key: primary_key,
                                  foreign_keys: foreign_keys }
    end

    def initialize(connection_pooler)
      @connection = connection_pooler.connection
      adapter = connection_pooler.connection_pool.spec.config[:adapter]

      @registration = known_adapters[adapter.to_sym] || {}
      raise Automodel::UnregisteredAdapter, adapter unless @registration
    end

    def tables
      @tables ||= if @registration[:tables].present?
                    @registration[:tables].call(@connection)
                  else
                    @connection.tables
                  end
    end

    def columns(table_name)
      table_name = table_name.to_s

      @columns ||= {}
      @columns[table_name] ||= if @registration[:columns].present?
                                 @registration[:columns].call(@connection, table_name)
                               else
                                 @connection.columns(table_name)
                               end
    end

    def primary_key(table_name)
      table_name = table_name.to_s

      @primary_keys ||= {}
      @primary_keys[table_name] ||= if @registration[:primary_key].present?
                                      @registration[:primary_key].call(@connection, table_name)
                                    else
                                      @connection.primary_key(table_name)
                                    end
    end

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

    def qualified(table_name, context:)
      return table_name if table_name['.'].present?
      return table_name if context['.'].blank?

      "#{context.sub(%r{[^.]*$}, '')}#{table_name}"
    end

    def unqualified(table_name)
      table_name.split('.').last
    end
  end
end
